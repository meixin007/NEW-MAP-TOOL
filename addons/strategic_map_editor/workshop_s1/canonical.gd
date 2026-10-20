@tool
extends RefCounted
## Frozen authoring-hash numeric precision: 9 decimal places, sorted JSON keys.
## Avoids differing float parsers changing a cache identity by a sub-pixel ULP.
static func stringify(value: Variant) -> String:
	if value is int or value is float:
		if float(value)==0.0: return "0"
		return String.num(float(value),9)
	if value is Array:
		var values:=PackedStringArray()
		for item in value: values.append(stringify(item))
		return "["+",".join(values)+"]"
	if value is Dictionary:
		# Dot assignments can produce StringName keys in memory; JSON reloads
		# strings. Sort their textual names rather than Variant type order.
		var keys: Array[String]=[]
		for key in value.keys(): keys.append(str(key))
		keys.sort()
		var fields:=PackedStringArray()
		for key in keys: fields.append(JSON.stringify(str(key))+":"+stringify(value[key]))
		return "{"+",".join(fields)+"}"
	return JSON.stringify(value)
static func digest(value: Variant) -> String:
	return stringify(value).sha256_text()
