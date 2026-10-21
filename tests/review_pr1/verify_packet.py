"""Read-only, standard-library evidence hashes and independent PNG reconstruction."""
from pathlib import Path
import argparse, hashlib, json, struct, zlib

def png(path):
    data=path.read_bytes();assert data[:8]==b'\x89PNG\r\n\x1a\n'
    offset=8;compressed=bytearray()
    while offset<len(data):
        size=struct.unpack_from('>I',data,offset)[0];kind=data[offset+4:offset+8];block=data[offset+8:offset+8+size]
        assert zlib.crc32(kind+block)&0xffffffff==struct.unpack_from('>I',data,offset+8+size)[0]
        if kind==b'IHDR':width,height,bits,color,compression,filtering,interlace=struct.unpack('>IIBBBBB',block)
        elif kind==b'IDAT':compressed.extend(block)
        offset+=12+size
    assert bits==8 and color in (2,6) and compression==filtering==interlace==0
    channels=4 if color==6 else 3;stride=width*channels;raw=zlib.decompress(compressed);output=bytearray();prior=bytearray(stride)
    assert len(raw)==height*(stride+1)
    for y in range(height):
        mode=raw[y*(stride+1)];row=bytearray(raw[y*(stride+1)+1:(y+1)*(stride+1)])
        assert mode in range(5)
        for x in range(stride):
            left=row[x-channels] if x>=channels else 0;above=prior[x];corner=prior[x-channels] if x>=channels else 0
            if mode==1:predict=left
            elif mode==2:predict=above
            elif mode==3:predict=(left+above)//2
            elif mode==4:
                p=left+above-corner;dist=[abs(p-left),abs(p-above),abs(p-corner)];predict=(left,above,corner)[dist.index(min(dist))]
            else:predict=0
            row[x]=(row[x]+predict)&255
        if channels==4:output.extend(row)
        else:
            for x in range(0,stride,3):output.extend(row[x:x+3]);output.append(255)
        prior=row
    return width,height,output

def verify(root):
    index=json.loads((root/'INDEX.json').read_text(encoding='utf-8'))
    for item in index['files']:
        file=(root/item['path']).resolve();assert file.is_relative_to(root.resolve())
        assert file.stat().st_size==item['bytes'] and hashlib.sha256(file.read_bytes()).hexdigest()==item['sha256'],item['path']
    bundle=root/'pixels';m=json.loads((bundle/'manifest.json').read_text(encoding='utf-8'))
    for name,digest in m['files'].items():
        file=(bundle/name).resolve();assert file.is_relative_to(bundle.resolve())
        assert hashlib.sha256(file.read_bytes()).hexdigest()==digest,name
    width,height,expected=png(bundle/'composite.png');actual=bytearray(len(expected));covered=bytearray(width*height)
    for tile in m['tiles']:
        tw,th,content=png(bundle/tile['path']);x,y=map(int,tile['pixel_origin'])
        assert tile['gutter']==0 and [tw,th]==tile['pixel_size']==tile['stored_size'] and tile['core_rect']==[0,0,tw,th]
        assert x>=0 and y>=0 and x+tw<=width and y+th<=height
        for row in range(th):
            start=(y+row)*width+x;assert not any(covered[start:start+tw]);covered[start:start+tw]=b'\1'*tw
            actual[start*4:(start+tw)*4]=content[row*tw*4:(row+1)*tw*4]
    assert all(covered) and actual==expected
    # Independent float64 straight-alpha source-over; quantize only once.
    values=[0.0]*len(expected)
    for layer in m['layers']:
        lw,lh,content=png(bundle/layer['path']);assert (lw,lh)==(width,height)
        for i in range(0,len(content),4):
            if not content[i+3]:continue
            alpha=content[i+3]/255.0;prior=values[i+3]*(1-alpha);total=alpha+prior
            for c in range(3):values[i+c]=(content[i+c]*alpha+values[i+c]*prior)/total
            values[i+3]=total
    errors=[]
    for i,value in enumerate(values):
        if i%4==3:value*=255
        # Values are nonnegative; Godot roundi rounds half away from zero.
        errors.append(abs(max(0,min(255,int(value+0.5)))-expected[i]))
    maximum=max(errors);fraction=sum(n>1 for n in errors)/len(errors)
    assert maximum<=2 and fraction<=0.0001,(maximum,fraction)
    return dict(passed=True,indexed_files=len(index['files']),tile_max_channel_error=0,layer_max_channel_error=maximum,layer_fraction_above_one=fraction)

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('evidence',type=Path);args=parser.parse_args()
    try:print(json.dumps(verify(args.evidence),indent=2))
    except (AssertionError,OSError,ValueError,KeyError) as exc:raise SystemExit('EVIDENCE FAILED: '+str(exc))
