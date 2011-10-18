; self references (tree) syntax: 
;   / is root object
;   sub objects referenced by index
;   if reference ends with "k" it is the key-object at that index
;   each nest level adds another "/"
;
; e.g.
; /       refers to root itself
; /2      refers to the root's second index value
; /4k     refers to the root's fourth index *key* (object-key)
; /1/5k/3 refers to: root first index value -> fifth index key -> third index value

LSON( obj_text, seps = "" )
{
    return IsObject(obj_text) ? LSON_Serialize(obj_text, seps) : LSON_Unserialize(obj_text)
}

LSON_Serialize( obj, seps = "", lobj = "", tpos = "" ) 
{
    array := True
    
    tpos .= "/"
    if !IsObject(lobj)
        lobj := Object("r" &obj, tpos) ; this root object is static through all recursion
    sep := seps._maxindex() ? seps.remove(1) : ", "
    
    for k,v in obj
    {
        retObj .= sep
        
        if IsObject(k)
            retObj .= LSON_GetObj(k, seps.clone(), lobj, tpos A_Index "k")
        else
            retObj .= k ~= "^[a-zA-Z0-9#_@$]+$" ? k : LSON_Normalize(k)
        retObj .= ": "
        
        if IsObject(v)
            v := LSON_GetObj(v, seps.clone(), lobj, tpos A_Index)
        else
            v := v+0 != "" ? v : LSON_Normalize(v)
        
        retObj .= v
        
        if (array := array && (k + 0 != "") && (k == A_Index) && (k == Abs(k)) && (k == Floor(k)))
            retArr .= sep v
    }
    if array
        ret := "[" SubStr(retArr, 1 + StrLen(sep)) "]"
    else
        ret := "{" SubStr(retObj, 1 + StrLen(sep)) "}"
    return ret
}

LSON_GetObj( obj, seps, lobj, tpos ) 
{
    if (lobj.HasKey("r" &obj))
        return lobj["r" &obj]
    lobj.insert("r" &obj, tpos)
    return IsFunc(obj) ? obj.Name "()" : LSON_Serialize(obj, seps.clone(), lobj, tpos)
}

LSON_Unserialize( _text ) 
{
    tree := []
    stack := []
    _text := RegExReplace(_text, "^\s++") ; remove leading whitespace
    pos := 1
    
    ret := Object()
    
    this := { objtype: SubStr(text, 1, 1), tpos: "/", ref: ret, idx: 0, key: "", next: ("value" OR "key") }
    stack.insert(1, this)
    tree.insert(stack[1,"tpos"], &stack[1,"ref"])
    
    while stack.maxindex() && ++pos <= StrLen(_text)
    {
        c := SubStr(_text, pos, 1)
        if InStr(" `t`r`n", c) ;whitespace
            continue
        
        text := SubStr(_text, pos)
        this.idx++
        
        if RegExMatch(text, "^""(?:[^""]|"""")++""", token) ;string
            pos += StrLen(token), tokentype := "string"
        else if RegExMatch(text, "^\d++(?:\.\d++)?|0x[\da-fA-F]++", token) ; number
            pos += StrLen(token), tokentype := "number"
        else if RegExmatch(text, "^[\w#@$]++(?:\(\))?", token) ;identifier
            pos += Strlen(token), tokentype := "identifier"
        ; else if ;object reference
        else if InStr("[{", c)
        {
            tokentype := "object"
            new_this := { objtype: c, tpos: "/", ref: Object(), idx: 0, key: "" }
            
            continue
        }
        else
            throw Expected token, got: "%c%"
        
        if (this.objtype = "[")
            this.ref[this.idx] := token
        else if (this.next = "key")
            this.key := token
        else
            this.ref[this.key] := token
        
        while InStr(" `t`r`n", SubStr(text, pos+1, 1) ;trim whitespace after token
            pos++
        
        c := SubStr(_text, pos, 1)
        pos++
        
        if (this.objtype = "[")
            if (c = ",")
                continue
            if (c = "]")
            {
                stack.remove()
                continue
            }
            else
                throw unexpected character
        else
            if (this.next = "value" ? c = "," : c = ":")
            {
                this.next := this.next = "value" ? "key" : "value"
                continue
            }
            else if (this.next = "value" && c = "}")
            {
                stack.remove()
                continue
            }
            else
                throw unexpected character
    }
    return token
}

LSON_Normalize(text) 
{
    text := RegExReplace(text,"``","````")
    text := RegExReplace(text,"`%","```%")
    text := RegExReplace(text,"`r","``r")
    text := RegExReplace(text,"`n","``n")
    text := RegExReplace(text,"`t","``t")
    while RegExMatch(text, "[\x0-\x19]", char) ; change control characters
        text := RegExReplace(text, char, "``x" Format("{1:02X}", asc(char)))
    return """" text """"
}

LSON_UnNormalize(text)
{
    text := SubStr(text, 2, -1) ;strip quotes
    while RegExMatch(text, "(?<!``)(````)*+``x(..)", char)
        text := RegExReplace(text, "(?<!``)(````)*+``x" char2, "$1" Chr("0x" char2))
    Transform, text, Deref, %text%
    return text
}

; These will not be used until a reliable method of determining whether an object contains binary data is found
LSON_BinToString(obj, k, len = "")
{
    vsz := len ? len*(1+A_IsUnicode) : obj.GetCapacity(k)
    vp  := obj.GetAddress(k)
    VarSetCapacity(outsz, 4, 0)
    DllCall("Crypt32.dll\CryptBinaryToString", "ptr", vp, "uint", vsz, "uint", 0xC, "ptr", 0   , "ptr", &outsz, "CDECL uint")
    NumGet(outsz)
    VarSetCapacity(out, NumGet(outsz)*(1+A_IsUnicode), 0)
    DllCall("Crypt32.dll\CryptBinaryToString", "ptr", vp, "uint", vsz, "uint", 0xC, "ptr", &out, "ptr", &outsz, "CDECL uint")
    return out
}

LSON_StringToBin(str, obj, k)
{
    VarSetCapacity(sz, 4)
    DllCall("Crypt32.dll\CryptStringToBinary", "ptr", &str, "UInt", 0, "UInt", 0xC, "ptr",  0, "ptr", &sz, "ptr", 0, "ptr", 0, "CDecl")
    obj.SetCapacity(k, NumGet(sz))
    pk := obj.GetAddress(k)
    DllCall("Crypt32.dll\CryptStringToBinary", "ptr", &str, "UInt", 0, "UInt", 0xC, "ptr", pk, "ptr", &sz, "ptr", 0, "ptr", 0, "CDecl")
}
