function tagvalue($awsobject, $tag){
    #returns the value of the specified AWS tag for the imput object
    if ($awsobject.PSobject.Properties.name -match "Tags"){
        $index = $awsobject.tags.key.indexof($tag)
        if ($index -lt 0){ Return "Tag not Found" }
        else {return $awsobject.tags.value[$index] }
    }
    Else{"Object has no Tags"}
}
