
;; ================================================
;; Script: xml-object.r
;; downloaded from: www.REBOL.org
;; on: 4-Nov-2008
;; at: 6:09:51 UTC
;; owner: brianwisti [script library member who can
;; update this script]
;; ================================================
;; ==================================================
;; email address(es) have been munged to protect them
;; from spam harvesters.
;; If you were logged on the email addresses would
;; not be munged
;; ==================================================
REBOL [
    Title: "Convert an XML-derived block structure into objects."
    File:  %xml-object.r

    Date:  2-Mar-2005
    Version: 1.0.5
    Author: "Brian Wisti"
    Email:  %brianwisti--yahoo--com
    Author: "Gavin F. McKenzie"
    License: "Unknown"
    library: [
        level: 'advanced
        platform: 'all
        type: 'module
        domain: [markup web xml]
        support: %brianwisti--yahoo--com
        tested-under: none
        license: none
        see-also: "xml-parse.r"
    ]

    Purpose: {
        This script creates a function "xml-to-object" that converts
        a series of nested blocks, created from an XML document by 
        parse-xml, into a series of nested objects that represent 
        the original content of the XML document processed.
    }

    History: [
        1.0.0 [17-Jul-2001 "First public release."]
        1.0.1 [17-Jul-2001 "Support for mixed content."]
        1.0.2 [06-Sep-2001 "Fixed a bug handling empty elements."]
        1.0.3 [22-Sep-2001 {Fixed a bug handling a mixture of 
                            unique and multiply occuring elements
                            sharing the same enclosing element.}]
        1.0.4 [29-Sep-2001 {Fixed a bug improperly ignoring whitespace.
                            Changed switch-es to use type?/word.}]
        1.0.5 [2-Mar-2005 {Downloaded from web.archive.org, 
                             changed some names, and uploaded 
                             to REBOL.org} ]
    ]

    Acknowledgments: {
        Many thanks to Mike Hansen for finding and reporting defects
        in this script.  

      Gavin F. MacKenzie wrote the original releases of this file,
      so it just plain wouldn't have happened without him. I hope he
      knows we're grateful and we hope he's doing well - wherever he's
      disappeared to!
    }

]

xml-to-object: function [{
    Convert a series of nested blocks, created from an XML document by
    parse-xml, into a series of nested objects that represent the original 
    content of the XML document processed.

    Returns the root object.
}
    document [block!] "The block representing the processed XML document."
][
    name
    children
    child attr-list
    contains-char-content 
    contains-element-content
    content-model
    potential-new-content
    new-content
    is-allspace
    do-character-content
    do-element-content
    add-mixed-content
    get-mixed-value
][
    is-allspace: function [s] [] [
        either (type? s) = string! [
            s: copy s
        ][
            s: form copy s
        ]
        s: trim/all s
        either (length? s) = 0 [
            return true
        ][
            return false
        ]
    ]

    do-character-content: func [
        children [string!]
    ][
        append new-content reduce [to-set-word 'value? children]
        remove next next document
    ]

    do-empty-content: func [
    ][
        append new-content reduce [to-set-word 'value? ""]
        remove next next document
    ]

    do-element-content: func [
        children [block!]
        /local entry
    ][
        ;
        ; Process all child content of this element
        ;
        forall children [
            potential-new-content: xml-to-object children/1
            ;
            ; Is there already an object member known by this name?
            ; (i.e. does it look like this is the beginning of
            ;  multiply occurring elements?)
            ;
            entry: find new-content (to-set-word potential-new-content/1)
            ;
            ; Yes, there is already an object member known by this name
            ;
            either entry [
                if entry/3 = 'object! [
                    ; ...so we need to transform the existing object member
                    ; from a single object into a block of objects,
                    ; and append the potential-new-content into the block
                    ;
                    change/part at entry 3 reduce ['block! 'reduce] 1
                    change/only at entry 5 reduce [
                        'make 'object! entry/5
                    ]
                ]
                append entry/5 (copy/part at potential-new-content 2 3)
            ][
                append new-content potential-new-content
            ]
        ]
    ]

    add-mixed-content: func [
        children [string! block!]
        /local v
    ][
        either (empty? new-content) or 
               (none? find new-content to-set-word 'content?) [
            append new-content reduce [
                to-set-word 'content? 
                    'make 'block! reduce [children] 
                to-set-word 'value? 
                    'does [get-mixed-value self]
            ]
        ][
            v: find new-content to-set-word 'content?
            either (type? children) = string! [
                append v/4 children
            ][
                append v/4 to-word children/1
            ]
        ]
    ]

    get-mixed-value: function [
        obj [object!]
    ][
        item
        cooked-value?
    ][
        cooked-value?: copy "" 
        foreach item (reduce obj/content?) [
            either (type? item) = string! [
                append cooked-value? item
            ][
                append cooked-value? item/value?
            ]
        ]
        cooked-value?
    ]

    name: to-word document/1
    change document to-set-word document/1

    new-content: copy []
    contains-char-content: false
    contains-element-content: false
    content-model: 'empty

    ;
    ; Extract attributes and children
    ;
    attr-list:  document/2
    children:   document/3
    remove/part next document 2

    ;
    ; Determine the content model
    ;
    if not none? children [
        for i 1 (length? children) 1 [
            child: pick children i
            switch type?/word child [
                string! [
                    content-model: 'character
                    either is-allspace child [
                        contains-char-content: 'ignoreable-ws
                    ][
                        contains-char-content: 'true
                    ]
                ]
                block! [
                    contains-element-content: true
                    content-model: 'element
                ]
            ]
            if (contains-char-content = 'true) and 
               (contains-element-content = true) [
              content-model: 'mixed
              break
            ]
        ]
    ]

    ;
    ; Remove any ignoreable whitespace nodes
    ;
    if (contains-char-content = 'ignoreable-ws) and 
       (contains-element-content = true) [
        content-model: 'element
        while [not tail? children] [
            either (type? children/1) = string! [
                remove children
            ][
                children: next children
            ]
        ]
        children: head children
    ]

    ;
    ; Actually do the work of 'objectifying' the block
    ; 
    switch content-model [
        empty [
            do-empty-content
        ]
        character [
            do-character-content children/1
        ]
        element [
            do-element-content children
        ]
        mixed [
            forall children [
                switch type?/word children/1 [
                    string! [
                        add-mixed-content children/1
                    ]
                    block! [
                        add-mixed-content children/1
                        do-element-content copy/part children 1
                    ]
                ]
            ]
        ]
    ]

    ;
    ; Process attributes
    ;
    if (not none? attr-list) [
        forskip attr-list 2 [
            change attr-list to-set-word attr-list/1
        ]
        attr-list: head attr-list
        append new-content attr-list
    ]

    ;
    ; Insert the result of all our hard work into the block
    ;
    if not empty? new-content [
        insert/only at document 2 new-content
        insert at document 2 reduce ['make 'object!]
    ]

    document
]

