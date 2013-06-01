Rebol [
	title: "MakeDocProConverter"
	version: 0.0.1
	file: %mdp2asciidoc.r
	author: "Graham Chiu"
	date: 3-Jan-2013
	purpose: {convert makedocpro markup to asciidoc.  Abused Carl's original makedoc2.r for this.  Uses rebol/view.}

comment {
REBOL [
	Title: "MakeDoc 2 - The REBOL Standard Document Formatter"
	Version: 2.5.7
	Copyright: "REBOL Technologies 1999-2005"
	Author: "Carl Sassenrath"
	File: %mdp2asciidoc.r
	Date: 2-Jan-2013 ;10-Mar-2007 ;10-Jan-2005
	Purpose: {
		This is the official MakeDoc document formatter that is used by
		REBOL Technologies for all documentation. It is the fastest and
		easiest way to create good looking documentation using any text
		editor (even ones that do not auto-wrap text). It creates titles,
		headings, contents, bullets, numbered lists, indented examples,
		note blocks, and more. For documentation, notes, and other info
		visit http://www.rebol.net/docs/makedoc.html
	}
	Usage: {
		Create a text document in any editor. Separate each paragraph
		with a blank line. Run this script and provide your text file.
		The output file will be the same name with .html following it.
		If you use REBOL/View the output file will be displayed in
		your web browser as well.

		You can also call this script from other scripts (e.g. CGI).
		These are supported:

			do %makedoc2.r

			do/args %makedoc2.r %document.txt

			do/args %makedoc2.r 'load-only
			doc: scan-doc read %file.txt
			set [title out] gen-html/options doc [(options)]
			write %out.html out
	}
	Library: [
		level: 'intermediate
		platform: 'all
		type: [tool]
		domain: [html cgi markup]
		tested-under: none
		support: none
		license: 'BSD
		see-also: none
	]
]
}
]

script-code: none
; 3-Jan-2013 GC
nws: complement charset [ #" " #"^-" #"^/"  #"<" #","]
ntilde: complement charset [ #" " #"~" ]
punctuation: charset [ #"." #"!" #"," #";" ]

npunct: complement punctuation
space: charset " ^-"
delimiter: union punctuation charset [ #" " #"^-" #"," #"." ]
non-delimiter: complement delimiter


; Below you can specify an HTML output template to use for all your docs.
; See the default-template example below as a starting suggestion.
template-file: %template.html  ; Example: %template.html

; There are three parts to this script:
;   1. The document input scanner.
;   2. The document output formatter (for HTML).
;   3. The code that deals with input and output files.

;clean script
context [
out: none   ; output text
    spaced: off ; add extra bracket spacing
    indent: ""  ; holds indentation tabs

    emit-line: func [] [append out newline]

    emit-space: func [pos] [
        append out either newline = last out [indent] [
            pick [#" " ""] found? any [
                spaced
                not any [find "[(" last out find ")]" first pos]
            ]
        ]
    ]

    emit: func [from to] [emit-space from append out copy/part from to]

    set 'clean-script func [
        "Returns new script text with standard spacing."
        script "Original Script text"
        /spacey "Optional spaces near brackets and parens"
        /local str new
    ] [
        spaced: found? spacey
        clear indent
        out: append clear copy script newline
        parse script blk-rule: [
            some [
                str:
                newline (emit-line) |
                #";" [thru newline | to end] new: (emit str new) |
                [#"[" | #"("] (emit str 1 append indent tab) blk-rule |
                [#"]" | #")"] (remove indent emit str 1) break |
                skip (set [value new] load/next str emit str new) :new
            ]
        ]
        remove out ; remove first char
    ]
]

parse-rules: copy [] 
do create-parse-rules: func [ /local mark1 mark2 mark3 mark4 rule][
	foreach [ start end replace1 replace2 ] [
		<b> </b> "*" "*" 
		<i> </i> "_" "_"
		<tt> </tt> "+" "+"
		<u> </u> "[underline]#" "#"
	][
		rule: compose/deep copy  [ to (start) mark1: (start) mark2: some nws mark3: (end) mark4: ]
		append/only rule to-paren compose/deep [ mark1: change/part mark1 reduce [ (replace1) copy/part mark2 mark3 (replace2) ] mark4 ]
		append rule [ :mark1 ]
		append/only parse-rules rule
	]
]

change-hiliting: func [ data /local mark1 mark2 txt ][
	foreach rule parse-rules [
		parse/all data [ any rule to end ]
	]
	parse/all data  [ some 
			[ to "f:" mark1: "f:" copy txt some non-delimiter
			( replace mark1 join "f:" txt rejoin [ "+" txt "+" ] ) ]
			to end 
	]
	parse/all data  [ some 
			[ to "w:" mark1: "w:" copy txt some non-delimiter
			( replace mark1 join "w:" txt rejoin [ "+" txt "+" ] ) ] 
			to end 
	]
	parse/all data  [ some 
			[ to "~" mark1: "~" copy txt to "~" mark2:
			( change/part mark2 "+" 1 change/part mark1 "+" 1) ] 
			to end 
	]


	data
]

*scanner*: context [

;-- Debugging:
verbose: off
debug: func [data] [if verbose [print data]]

;-- Module Variables:
text: none
para: none
code: none
title: none
left-flag: off
opts: [] ;[no-toc no-nums]
out: [] ; The output block (static, reused)
option: none



;--- Parser rules for the Makedoc text language (top-down):

rules: [some commands]
commands: [
	newline
	here: (debug ["---PARSE:" copy/part here find here newline])

	;-- Document sections:
	| ["===" | "-1-"] text-line (emit-section 1)
	| ["---" | "-2-"] text-line (emit-section 2)
	| ["+++" | "-3-"] text-line (emit-section 3)
	| ["..." | "-4-"] text-line (emit-section 4)
	| "###" to end (emit end none) ; allows notes, comments to follow

	;-- Common commands:
	| #"*" [
		  [">>" | "**"] text-block (emit bullet3 para)
		| [">"  | "*" ] text-block (emit bullet2 para)
		| text-block (emit bullet para)
	]
	| #"#" [
		  ">>" text-block (emit enum3 para)
		| ">"  text-block (emit enum2 para)
		| text-block (emit enum para)
	]
	| #":" define opt newline (emit define reduce [text para])

;   ">>" reserved
;   "<<" reserved

	;-- Enter a special section:
	| #"\" [
		  "in" (emit indent-in none)
		| "note" text-line (emit note-in text)
		| "table" text-line (emit table-in text)
		| "group" (emit group-in none)
		| "center" (emit center-in none)
		| "column" (emit column-in none)
	]

	;-- Exit a special section:
	| #"/" [
		  "in" (emit indent-out none)
		| "note" (emit note-out none)
		| "table" (emit table-out none)
		| "group" (emit group-out none)
		| "center" (emit center-out none)
		| "column" (emit column-out none)
	]

	;-- Extended commands (all begin with "="):
	| #";" text-block ; comments and hidden paragraphs
	| #"=" [
		  #"=" output (emit output trim/auto code)
		| "image" image
		| "row" (emit table-row none)
		| "column" (emit column none) ; (for doc, not tables)
		| "options" [
			any [
				spaces copy option [
					  "toc"
					| "nums"
					| "indent"
					| "no-indent"
					| "no-toc"
					| "no-nums"
					| "no-template"
					| "no-title"
					| "old-tags"
					| "root-images"
				] (append opts to-word option)
			]
		]
		| "template" some-chars (repend opts ['template as-file text])
	]

	;-- Primary implied paragraph types:
	| example (emit code trim/auto detab code)
	| paragraph (
		either title [emit para para][emit title title: para]
	)
	| skip (debug "???WARN:  Unrecognized")
]

; 3-Jan-2013 GC
space: charset " ^-"

nochar: charset " ^-^/"
chars: complement nochar
spaces: [any space]
some-chars: [some space copy text some chars]
text-line:  [any space copy text thru newline]
text-block: [any space paragraph opt newline] ; ignore leading space, extra NL !???
paragraph: [copy para some [chars thru newline]]
example:   [copy code some [indented | some newline indented]]
indented:  [some space chars thru newline]
output:    [
	some space copy code thru newline
	any ["==" ["^-" | "  "] copy text thru newline (append code text)]
] 
define:    [copy text to " -" 2 skip text-block]
image: [
	left? any space copy text some chars (
		if text/1 = #"%" [remove text] ; remove %file
		text: as-file text
		emit image reduce [text pick [left center] left-flag]
	) 
]
left?: [some space "left" (left-flag: on) | none (left-flag: off)]

as-file: func [str] [to-file trim str]

;-- Output emitters:

; 3-Jan-2013 GC
emit: func ['word data /local mark1 mark2 txt] [
	debug ["===EMIT: " word]
	if block? word [word: do word] ;????
	if string? data [
		trim/tail data
		; change-hiliting data
	]
	repend out [word data]
]

emit-section: func [num] [
	emit [to-word join "sect" num] text
	title: true
]

;-- Export function to scan doc. Returns format block.
set 'scan-doc func [str /options block] [
	clear out
	title: none
	
	; pre-process makedocpro
	foreach [ old new ] [
		"^//table" "^/^//table"
		"^/\table^/" "^/\table^/^/"
		"^//note^/" "^/^//note^/^/"
		"^/\note^/" "^/\note^/^/"
		"^/:" "^/^/:"
		"|^/^/^/" "|"
		"||^/^/" "||"
		"^/*" "^/^/*"
		"^/#" "^/^/#"
		"=TOC" ""		
	][
		replace/all str old new
	]
	; see if there's a date header we need to change to :DATE: format	
	use [ mark ][
		 either parse/all str [ thru "^/^/" thru "^/" to "Date:" mark: (insert mark ":" ) to end ][
			print "updated date style for asciidoc"
		][
			print "failed to update date header"
		]
	]

	if options [
		if find block 'no-title [title: true]
	]
	emit options opts
	str: join str "^/^/###" ; makes the parse easier
	parse/all detab str rules
	if verbose [
		n: 1
		foreach [word data] out [
			print [word data]
			if (n: n + 1) > 5 [break]
		]
	]
	copy out
]
]

;-- HTML Output Generator ----------------------------------------------------

*html*: context [

;-- HTML foprmat global option variables:
no-nums:    ; Do not use numbered sections
no-toc:     ; Do not generate table of contents
no-title:   ; Do not generate a title or boilerplate
no-indent:  ; Do not indent each section
no-template: ; Do not use a template HTML page
old-tags:   ; Allow old markup convention (slower)
root-images: ; Images should be located relative to /
	none

toc-levels: 2  ; Levels shown in table of contents
image-path: "" ; Path to images

set 'gen-html func [
	doc [block!]
	/options opts [block!]
	/local title template tmp
][
	clear out ; (reused)
	group-count: 0

	; Options still need work!!!
	no-nums:
	no-toc:
	no-title:
	no-indent:
	no-template:
	old-tags:
	root-images:
		none

	set-options opts: any [opts []]
	set-options select doc 'options
	if root-images [image-path: %/]

comment {
	; Template can be provided in =template or in
	; options block following 'template. If options
	; has 'no-template, then do not use a template.
	if not no-template [
		template: any [select opts 'template select doc 'template template-file]
		if file? template [template: attempt [read template]]
		if not template [template: trim/auto default-template]
	]
}

	; Emit title and boilerplate:
	if not no-title [title: emit-boiler doc]

	; Emit table of contents:
	clear-sects
	if not no-toc [
		emit-toc doc
		clear-sects
	]

comment {
.An example table
[options="header,footer"]
|=======================
|Col 1|Col 2      |Col 3
|1    |Item 1     |a
|2    |Item 2     |b
|3    |Item 3     |c
|6    |Three items|d
|=======================
}	
	
	prior-cmd: none
	forskip doc 2 [
		; If in a table, emit a cell each time.
		if all [
			in-table
			zero? group-count ; do not emit cell if in group
			not find [table-out table-row] doc/1 
			not find [table-in table-row] prior-cmd
		][
			; emit-table-cell
			emit "|"
		]
		if in-center [ emit "|" ]

		switch prior-cmd: doc/1 [
			para        [emit-para doc/2]
			sect1       [emit-sect 1 doc/2]
			sect2       [emit-sect 2 doc/2]
			sect3       [emit-sect 3 doc/2]
			sect4       [emit-sect 4 doc/2]
			bullet      [emit-item doc doc/1]
			bullet2     [emit-item doc doc/1]
			bullet3     [emit-item doc doc/1]
			enum        [emit-item doc doc/1]
			enum2       [emit-item doc doc/1]
			enum3       [emit-item doc doc/1]
			code        [doc: emit-code doc]
			output      [doc: emit-code doc]
			define      [emit-def doc]
			image       [emit-image doc/2]
			table-in    [emit-table doc/2 ]
			table-out   [emit-table-end]
			table-row   [emit-table-row]
			center-in   [fake-center-in ] ;emit <center>]
			center-out  [fake-center-out ] ;emit </center>]
			note-in     [emit-note doc/2]
			note-out    [emit-note-end]
			group-in    [group-count: group-count + 1]
			group-out   [group-count: max 0 group-count - 1]
			indent-in   [emit "[indented]"] ; 2-Jan-2013 GC
			indent-out  [emit newline ] ; 2-Jan-2013 GC
			column-in   [emit {<table border=0 cellpadding=4 width=100%><tr><td valign=top>}]
			column-out  [emit {</td></tr></table>}]
			column      [emit {</td><td valign=top>}]
		]
		; if in-header [ remove back tail out ] ; remove previous CR!
	]
	doc: head doc
	; emit </blockquote>

	if template [
		; Template variables all begin with $
		tmp: copy template ; in case it gets reused
		replace/all tmp "$title" title
		replace/all tmp "$date" now/date
		replace tmp "$content" out
		out: tmp
	]
	reduce [title out]
]

set-options: func [options] [
	if none? options [exit]
	foreach opt [
			no-nums 
			no-toc
			no-indent
			no-template
			no-title
			old-tags
			root-images
	][if find options opt [set opt true]]
	foreach [opt word] [
			nums no-nums
			toc no-toc
			indent no-indent
	][if find options opt [set word false]]
]

;-- HTML Emit Utility Functions:

out: make string! 10000

; 2-Jan-2013 GC remove newline
emit: func [data /ns] [
	; Primary emit function:
	; insert insert tail out reduce data newline
	; if in-header [ remove back tail out ] ; remove previous CR!
	insert tail out reduce data
]

wsp: charset " ^-^/" ; whitespace: sp, tab, return

emit-end-tag: func [tag] [
	; Emit an end tag from a tag.
	tag: copy/part tag any [find tag wsp tail tag]
	insert tag #"/"
	emit tag
]

emit-tag: func [text tag start end] [
	; Used to emit special one-sided tags:
	while [text: find text tag] [
		remove/part text length? tag
		text: insert text start
		text: insert any [find text end-char tail text] end
	]
]
end-char: charset [" " ")" "]" "." "," "^/"]

escape-html: func [text][
	; Convert to avoid special HTML chars:
	foreach [from to] html-codes [replace/all text from to]
	text
]
html-codes: ["&" "&amp;"  "<" "&lt;"  ">" "&gt;"]

; 2-Jan-2013 GC
emit-lines: func [text] [
	; Emit separate lines in normal font:
	; replace/all text newline <br>
	emit text
]

;-- HTML Document Formatting Functions:

fix-tags: func [text] [
	if old-tags [
		emit-tag text "<c>" "<tt>" "</tt>"
		emit-tag text "<w>" "<b><tt>" "</tt></b>"
		emit-tag text "<s>" "<b><i>" "</i></b>"
	]
	change-hiliting text
	text
]

comment {
format seems to be || is a row separator, and | is a column separator.  No newlines are allowed in the data
data: {face |
The face upon which the actor acts. ||
args |
A single value or block of multiple values.}
}

process-mdp-table: func [ data ][
	replace/all data newline ""
	if all [
		#"|" = last data
		#"|" <> first back back tail data
	][
		remove back tail data
		data: head data
	]
	replace/all data "||" "^/|"
]

; 2-Jan-2013 GC
; 4-Jan-2013 makedocpro all data for the table can come in a single line
emit-para: func [text] [
	; Emit standard text paragraph:
	emit either in-table [
		[	process-mdp-table text ]
	] [ [ newline change-hiliting text newline ]]
]


; 2-Jan-2013 GC
emit-code: func [doc] [
	emit [ newline "----" newline ] ;<pre>
	script-code: copy ""
	while [
		switch doc/1 [
			; code   [emit [ newline escape-html doc/2 newline]]
            code   [append script-code newline append script-code escape-html doc/2 append script-code newline ]
			; output [emit [<span class="output"> escape-html doc/2 </span>]]
			output [emit [ newline escape-html doc/2]]
		]
	][doc: skip doc 2]
	if error? set/any 'err try [
		emit clean-script script-code
	][
		emit script-code
		print "Clean script error"
		print script-code
		probe disarm err
	]
	emit [ newline "----" newline ] ; </pre>
	doc: skip doc -2
]
comment {
emit-code: func [doc] [
    ;emit <pre>
	script-code: copy ""
    while [
        switch doc/1 [
            code   [append script-code newline append script-code form escape-html doc/2 append script-code newline ]
            output [emit [<span class="output"> escape-html doc/2 </span>]]
        ]
    ][doc: skip doc 2]
    ;emit </pre>
	; probe clean-script
	emit clean-script script-code
    doc: skip doc -2
]
}

; 3-Jan-2013 GC
; image:<target>[<attributes>]
emit-image: func [spec /local tag] [
	; Emit image. Spec = 'center or default is 'left.
	emit [
		; either spec/2 = 'center [<p align="center">][<p>]
		newline "image:" image-path spec/1 "[" last split-path spec/1 "]" newline
		; join {<img src="} [(join image-path spec/1) {">}]
		; </p>
	]
]

in-center: false
; 3-Jan-2013 GC - center not supported
fake-center-in: does [
	; emit [ {[width="100%",frame="none", align="center"]} newline "|=============" newline ]
	; in-center: true
]

fake-center-out: does [
	; got to be an easier way to remove the extra "|"
	; remove back tail out
	; emit [ "|=============" newline ]
	; in-center: false
]


; only allows 3 levels of bullets
buls: [bullet bullet2 bullet3]
enums: [enum enum2 enum3]

bul-stack: []

; 2-Jan-2013 GC
; bul is of type buls or enums; only push a bul to bul-stack if the stack is empty, or, if the new bullet is different from last in stack
; Always emit the asciidoc bullet type
push-bul: func [bul /local fnd][
	if any [empty? bul-stack  bul <> last bul-stack][
		append bul-stack bul
		emit newline
	]
		; true picks "*" which is unordered list
		; false picks "." which is ordered list
		; emit pick ["*" "."] found? find buls bul
		either found? fnd: find buls bul [
			emit pick [ "*" "**" "***" ] index? fnd
		][
			if found? fnd: find enums bul [
				emit pick [ "." ".." "..." ] index? fnd
			]
		]
	;]
]

; 2-Jan-2013 GC
; only remove bul from bul-stack if not empty, and new bul differs from last, and bul is in the stack above last
pop-bul: func [bul /local here][
	; here is true if bul is any valid bullet or enums
	here: any [find buls bul find enums bul]
	while [
		all [
			not empty? bul-stack
			bul <> last bul-stack
			any [
				not here ; not bullet or enum
				find next here last bul-stack
				all [here: find bul-stack bul not tail? here]
			]
		]
	][
		; print ['pop bul mold bul-stack]
		remove back tail bul-stack
	]
]

; 2-Jan-2013 GC 
; 8-Jan-2013 markup text in bullets
; doc: [ bullet "Bullet 1" bullet "Bullet 2 - has sub-bullets" bullet2 "Bullet 2.1" ]
emit-item: func [doc item /local tag][
	push-bul item
	emit [ " " change-hiliting fix-tags doc/2 newline ]
	pop-bul doc/3
]


;[horizontal]
;.Labeled horizontal
;Term 1:: Definition 1
; 3-Jan-2013 GC
emit-def: func [doc] [
	; Emit indented definitions table. Start and end it as necessary.
	if doc/-2 <> 'define [
		; emit {<table cellspacing="6" border="0" width="95%">}
		emit [ newline "[horizontal]" newline ]
	]
	emit [
		;<tr><td width="20"> "&nbsp;" </td>
		;<td valign="top" width="80">
		;<b> any [doc/2/1 "&nbsp;"] </b></td>
		;<td valign="top"> fix-tags any [doc/2/2 " "] </td>
		;</tr>
		join doc/2/1 ":: " 
		change-hiliting  doc/2/2
		newline
	]
	; if doc/3 <> 'define [emit {</table>}]
	if doc/3 <> 'define [ emit newline ]
]

; 2-Jan-2013 GC
emit-note: func [text] [
	; Start a note sidebar, centered on page:
	emit [ newline "." change-hiliting  text newline "[NOTE]" ]
]

; 2-Jan-2013 GC
emit-note-end: does [
	; End a note sidebar.
	emit [ newline ]
]

in-table: in-header: false

comment {
.An example table
[options="header,footer"]
|=======================
|Col 1|Col 2      |Col 3
|1    |Item 1     |a
|2    |Item 2     |b
|3    |Item 3     |c
|6    |Three items|d
|=======================
}

emit-table: does [
	in-table: true
	in-header: true
	; emit {<table border="0" cellspacing="1" cellpadding="4" bgcolor="#505050"> <tr bgcolor="silver"><td><b>}
	; emit [ newline {[options="header"]} newline]  ;; no headers in makedoc tables
	emit [ newline ]
	emit [ "|======================="  newline "|"]
]

emit-table-end: does [
	in-table: false
	; emit "</td></tr></table>"
	emit [ newline "|=======================" newline ]
]

emit-table-cell: does [ 
	emit pick [{</b></td><td><b>} {</td><td valign="top" bgcolor="white">}] in-header
]

emit-table-row: does [
	in-header: false
	; emit {</td></tr><tr><td valign="top" bgcolor="white">}
	emit [ newline "|"]
]

;-- Section handling:

clear-sects: does [sects: 0.0.0.0]

next-section: func [level /local bump mask] [
	; Return next section number. Clear sub numbers.
	set [bump mask] pick [
		[1.0.0.0 1.0.0.0]
		[0.1.0.0 1.1.0.0]
		[0.0.1.0 1.1.1.0]
		[0.0.0.1 1.1.1.1]
	] level
	level: form sects: sects + bump * mask
	clear find level ".0"
	level
]

make-heading: func [level num str /toc /local lnk][
	; Make a proper heading link or TOC target.
	; Determine link target str. Search for [target] in front of heading.
comment { ; not required .. done thru javascript

	either parse str [
		"[" copy lnk to "]"
		s: to end
	][
		str: next s ; remove link target
	][
		lnk: join "section-" num
	]
	if not no-nums [str: rejoin [num pick [". " " "] level = 1 str]]
	rejoin either toc [
		[{<a class="toc} level {" href="#} lnk {">} str </a>]
	][
		[{<h} level + 1 { id="} lnk {">} str {</h} level + 1 {>}]
	]
}	
]

; -~^+
; 2-Jan-2013 GC
make-heading: func [level num str /toc /local lnk][
	tmp: copy ""
	rejoin [
		newline
		str
		newline
		head insert/dup copy "" pick "-~^^+" level length? str
	]
]

emit-sect: func [level str /local sn] [
	; Unindent prior level:
	; if all [not no-indent level <= 2 sects/1 > 0] [emit </blockquote>]
	sn: next-section level
	emit make-heading level sn str
	; if all [not no-indent level <= 2] [emit <blockquote>]
]

; 2-Jan-2013 GC
emit-toc: func [ ][
	; not required.  Uses command line options to generate toc
]

emit-boiler: func [doc /local title info temp] [
	; Output top boiler plate:
	title: any [
		select doc 'title
		select doc 'sect1
		"Untitled"
	]
	emit temp: rejoin [ title newline head insert/dup copy "" "=" length? title newline]
	foreach [word val] doc [
		if word = 'code [
			;emit {<blockquote><b>}
			emit-lines val
			emit newline
			;emit {</b></blockquote>}
			remove/part find doc 'code 2
			break
		]
		if not find [title template options] word [break]
	]
	title
]

]

do-makedoc: has [in-view? file msg doc] [

	in-view?: all [value? 'view? view?] ; Are we using View?

	; Get the file name from the script argument:
	file: system/script/args
	if any-string? file [file: to-file file] ; makes copy too

	; If no file provided, should we do the last file again?
	if all [
		not file
		exists? %last-file.tmp
	][
		file: load %last-file.tmp
		either confirm reform ["Reprocess" file "?"] [
			system/script/args: none
		][
			file: none
		]
	]

	; If no file still, then ask the user for the file name:
	if not file [
		either in-view? [
			file: request-file/only
		][
			file: ask "Filename? "
			file: all [not empty? trim file to-file file]
		]
	]

	; No file provided:
	if not file [exit]

	; File must exist:
	if not exists? file [
		msg: reform ["Error:" file "does not exist"]
		either in-view? [alert msg] [ask msg]
		exit
	]

	; Save this as the last file processed:
	save %last-file.tmp file

	; Process the file. Returns [title doc]
	doc: second gen-html scan-doc read file

	; Create output file name:
	append clear find/last file #"." ".txt"
	write file doc

	if all [in-view? not system/script/args] [browse file]
	file ; return new file (entire path)
]

; Start process (but caller may request it only be loaded):
if system/script/args <> 'load-only [do-makedoc]
