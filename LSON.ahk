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

;TODO: drop support for ahk-objects, and change all escape sequences to \

LSON( obj_text )
{
    return IsObject(obj_text) ? LSON_Serialize(obj_text) : LSON_Deserialize(obj_text)
}

LSON_Serialize( obj, lobj = "", tpos = "" ) 
{
    array := True,  tpos .= "/", sep := ", "
    if !IsObject(lobj)
        lobj := Object(&obj, tpos) ; this root object is static through all recursion
    for k,v in obj
    {
        retObj .= ", " (IsObject(k) ? LSON_GetObj(k, lobj, tpos A_Index "k") : LSON_Normalize(k)) ": "
               . v :=  (IsObject(v) ? LSON_GetObj(v, lobj, tpos A_Index)     : (v+0 != "" ? v : LSON_Normalize(v)))
        if (array := array && (k + 0 != "") && (k == A_Index))
            retArr .= ", " v
    }
    return array ? "[" SubStr(retArr,3) "]" : "{" SubStr(retObj,3) "}"
}

LSON_GetObj( obj, lobj, tpos ) 
{
    if (lobj.HasKey(&obj))
        return lobj[&obj]
    lobj[&obj] := tpos
    return IsFunc(obj) ? obj.Name "()" : LSON_Serialize(obj, lobj, tpos)
}

LSON_Deserialize( _text ) 
{
    tree  := []
    stack := []
    _text := RegExReplace(_text, "^\s++") ; remove leading whitespace
    pos := 1
    
    c := SubStr(_text, 1, 1)
    if !InStr("[{",c)
        throw "object not recognized"
    
    ret  := { type: c = "[" ? "arr" : "obj" , tpos: "/" , ref: Object() , idx: 0 , key: "" , mode: c = "[" ? "value" : "key" }
    stack.insert(ret)
    tree.insert(stack[1].tpos, &stack[1].ref)
    
    while stack.maxindex() && ++pos <= StrLen(_text) {
        c := SubStr(_text, pos, 1)
        if InStr(" `t`r`n", c) ;whitespace
            continue
        
        text := SubStr(_text, pos)
        this := stack[stackidx := stack.maxindex()]
        this.idx++
        
        if RegExMatch(text, "^""(?:[^""\\]|\\.)+""", token) ;string
            pos += StrLen(token), token := LSON_UnNormalize(token), tokentype := "string"
        else if RegExMatch(text, "^\d++(?:\.\d++(?:e[\+\-]?\d++)?)?|0x[\da-fA-F]++", token) ; number
            pos += StrLen(token), token += 0, tokentype := "number"
        else if (this.mode = "key") && RegExmatch(text, "^[\w#@$]++", token) ;identifier
            pos += StrLen(token), tokentype := "identifier"
        else if RegExMatch(text, "^(?!\.)[\w#@$\.]+(?<!\.)(?=\(\))", token) { ;function
            pos += StrLen(token)+2, tokentype := "function"
            if !IsFunc(token)
                throw "Function not found: " token "() at position " (pos-StrLen(token)-2)
            token := Func(token)
        }
        else if RegExMatch(text, "^(?:/\d+k?+)++", token) { ; self-reference
            pos += StrLen(token), tokentype := "reference"
            if !tree.HasKey(token)
                throw "Self-reference not found: " token " at position " (pos-StrLen(token))
            token := tree[token]
        }
        else if InStr("[{", c) {
            new_this := { type: c = "[" ? "arr" : "obj"
                        , tpos: (this.tpos!="/"?"/":"") this.idx (this.mode="key"?"k":"")
                        , ref: Object()
                        , idx: 0
                        , key: ""
                        , mode: c = "[" ? "value" : "key" }
            token := new_this.ref
            tokentype := "object"
            tree.insert(new_this.tpos, new_this.ref)
            stack.insert(new_this)
        }
        else
            throw "Expected token, got: '" c "' at position " pos
        
        if (this.type = "arr")
            this.ref[this.idx] := token
        else if (this.mode = "key")
            this.key := token
        else
            this.ref[this.key] := token, this.key := ""
        
        while pos < StrLen(_text) && InStr(" `t`r`n", SubStr(_text, pos, 1)) ;trim whitespace after token
            ++pos
        
        if (tokentype = "object")
            continue
        
        c := SubStr(_text, pos, 1)
        if (this.type = "arr") {
            if (c = "]")
                this.mode := "end"
            else if (c != ",")
                throw "Expected array separator/termination, got: '" c  "' at position " pos
        }
        else
            if (this.mode = "value" ? c = "," : c = ":")
                this.mode := this.mode = "value" ? "key" : "value"
            else if (this.mode = "value" && c = "}")
                this.mode := "end"
            else
                throw "Expected object " (this.mode = "key" ? "key/termination" : "value") ", got: '" c  "' at position " pos
        
        if (this.mode = "end")
            stack.remove(stackidx), pos++
    }
    return ret.ref
}

LSON_Normalize(text) 
{
    text := RegExReplace(text,"\\","\\")
    text := RegExReplace(text,"/","\/")
    text := RegExReplace(text,"`b","\b")
    text := RegExReplace(text,"`f","\f")
    text := RegExReplace(text,"`n","\n")
    text := RegExReplace(text,"`r","\r")
    text := RegExReplace(text,"`t","\t")
    text := RegExReplace(text,"""","\""")
    while RegExMatch(text, "[\x0-\x19]", char)
        text := RegExReplace(text, char, "\u" Format("{1:04X}", asc(char)))
    return """" text """"
}

LSON_UnNormalize(text)
{
    text := SubStr(text, 2, -1) ;strip outside quotes
    while RegExMatch(text, "(?<!\\)((?:\\\\)*+)\\u(....)", char)
        text := RegExReplace(text, "(?<!\\)((?:\\\\)*+)\\u" char2, "$1" Chr("0x" char2))
    text := RegExReplace(text,"\\""", """") ;un-escape quotes
    text := RegExReplace(text,"\\t","`t")
    text := RegExReplace(text,"\\r","`r")
    text := RegExReplace(text,"\\n","`n")
    text := RegExReplace(text,"\\f","`f")
    text := RegExReplace(text,"\\b","`b")
    text := RegExReplace(text,"\\/","/")
    text := RegExReplace(text,"\\\\","\")
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
