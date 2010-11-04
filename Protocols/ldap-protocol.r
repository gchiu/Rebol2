REBOL [
	Name: "LDAP Protocol"
	Purpose: "LDAP support"
	File: %ldap-protocol.r
	Version: 0.5.0
	Author: "Nenad Rakocevic"
	License: {
		Copyright 2010 Nenad Rakocevic. All rights reserved.

		Redistribution and use in source and binary forms, with or without modification, are
		permitted provided that the following conditions are met:

		   1. Redistributions of source code must retain the above copyright notice, this list of
			  conditions and the following disclaimer.

		   2. Redistributions in binary form must reproduce the above copyright notice, this list
			  of conditions and the following disclaimer in the documentation and/or other materials
			  provided with the distribution.

		THIS SOFTWARE IS PROVIDED BY NENAD RAKOCEVIC ``AS IS'' AND ANY EXPRESS OR IMPLIED
		WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND
		FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL NENAD RAKOCEVIC OR
		CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
		CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
		SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
		ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
		NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
		ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

		The views and conclusions contained in the software and documentation are those of the
		authors and should not be interpreted as representing official policies, either expressed
		or implied, of Nenad Rakocevic.
	}
	Usage: {
		port: open ldap://<server>[:<port-id>]		;-- default port used is 389
		
		result: find port <specs>					;-- <specs> is a block! value
		
		<specs>: [
			string!									;-- DN string!
			<filters>								;-- optional
			<options>								;-- optional
		]
		
		<filters>: 		
			o simple: filter <expr>
			o any expressions true: filter any [<expr> ...]
			o all expressions true: filter all [<expr> ...]
			o all expressions false: filter not [<expr> ...]
			o nested expressions: filter any [all [<expr> ...] not [<expr> ...]

		<expr>: 
			"attribute" [= | <= | >= | like] <value>
			| match "attribute" head | center | tail	;-- match attribute name pattern
			| present "attribute"						;-- require attribute name to be present in record
				
		<value>: string! | number!
		
		<options>:										;-- square brackets below denote list of alternatives
			some [
				scope [base | one]						;-- 
				| deref [search | find | always]		;-- alias resolution method
				| max-time integer!						;-- set maximum time for the request in seconds (default: 15s)
				| max-size integer!						;-- set maximum number of resulting records
				| only-attributes						;-- return only attributes (not working for now)
			]
			
		FIND returns a block! of objects or none! if no matching record found.
		
		close port										;-- sends a quit message to the server
	}
	Example: {
		p: open ldap://ldap.itd.umich.edu
		probe find p [
			"ou=People, dc=umich,dc=edu"
			filter sn = "elmer"
		]
		probe find p [
			"ou=People, dc=umich,dc=edu"
			filter sn = "elmer" only ["cn" "sn"]
			max-time 30									;-- triggers an error if reached!
			max-size 20									;-- triggers an error if reached!
		]
		probe find p [
			"ou=People, dc=umich,dc=edu"
			filter all [sn = "elmer" uid = "sjelmer"]
		]
		probe find p [
			"ou=People, dc=umich,dc=edu"
			filter all [sn = "elmer" not [uid = "sjelmer"]] only ["cn"]
		]
		close p
	}
]

make root-protocol [

	;copy*:	 get in system/words 'copy
	find*:	 get in system/words 'find
	;insert*: get in system/words 'insert
	;pick*: 	 get in system/words 'pick
	close*:  get in system/words 'close

	;-- BER encoding/decoding --
	BER: context [
		apps: none
		
		class-id: [
		;-- REBOL type  ID		BER type		Contructed?
	
			logic!		1		boolean				no
			integer!	2		integer				no
			-			3		bit-string			no
			string!		4		octet-string		no
			none!		5		null				no
			issue!		6		object-id			yes
			decimal!	9		real				no
			email!		10		enum				no
			block!		16		sequence			yes
			paren!		17		set					yes
			-			22		IA5-string			no
		]
	
		throw-error: func [msg][
			make error! reform ["BER Error:" msg "!"]
		]
		
		;----- BER decoding -----
		
		output: []
	
		decode-len: func [data][	
			if data/2 < 128 [return reduce [to integer! data/2 skip data 2]]
			if zero? data/2 [throw-error "unsupported Indefinite form"]
			error? try [
				return reduce [
					to integer! trim/head copy/part skip data 2 data/2 - 128
					skip data 2 + data/2 - 128
				]
			] throw-error "invalid field length"
		]
		
		decode-seq: func [data type /local seq end len value][
			seq: make type 3
			set [len value] decode-len data
			end: index? at value len
			data: value
			unless empty? data [
				until [
					set [len value] decode-len data
					decode-elem data seq
					end <= index? data: at value len + 1
				]
			]
			seq
		]
	
		decode-elem: func [data [binary!] out [any-block!] 
			/local b0 b1 res len-data value
		][
			b0: data/1
			unless zero? b0 and 128 [		;--- context value
				repend out [to tag! b0 and 31 res: decode-seq data block!]
				return res
			]
			either not zero? b0 and 64 [
				unless b0: find* apps to integer! b0 - 96 [
					print join "Decode error: unknown application code" b0
				]
				repend out [b0: first skip b0 -2 res: decode-seq data block!]
			][
				unless type: find* class-id b0 and 31 [
					print join "Decode error: unknown type " b0
				]
				either find* [sequence set] type/2 [
					res: decode-seq data any [all [type/2 = 'set paren!] block!]
				][
					set [b1 value] decode-len data
					len-data: copy/part value b1
	
					res: switch/default type/2 [
						boolean 	 [not zero? value/1]
						integer 	 [to integer! len-data]
						bit-string 	 [to string! len-data]
						octet-string [to string! len-data]
						null 		 [none]
						object-id 	 []
						real 		 []
						enum 		 [join to email! to integer! len-data #"@"]
					][print ["type inconnu: " mold type/2]]
				]
	
				either any-block? res [insert/only tail out res][
					insert tail out res
				]
			]
			res
		]
	
		decode: func [data [binary!]][
			clear output
			decode-elem data output
			first output
		]
	
		;----- BER encoding -----
		
		int-to-hex: func [int [integer!] /local out b][
			remove-each b out: debase/base to-hex int 16 [zero? to integer! b]
			out
		]
	
		encode-len: func [data [series!] /local len xlen xtra][
			either 127 < len: length? data [
				xlen: int-to-hex len
				xtra: int-to-hex 128 + length? xlen
				head insert tail xtra xlen
			][to char! length? data]
		]
	
		encode-seq: func [series /local seq][
			seq: make binary! 16
			forall series [
				either word? series/1 [
					insert tail seq encode/app series/1 series/2
					series: next series
				][
					either tag? series/1 [
						insert tail seq encode/ctx series/1 series/2
						series: next series
					][
						insert tail seq encode series/1
					]
				]
			]
			reduce [encode-len seq seq]
		]
	
		encode: func [data /app list /ctx arg /local out b0 b1 b2 type][
			out: make binary! 3
			type: type?/word data
			unless app [
				either ctx [
					b0: 128 or load to string! data 
					if any-block? arg [b0: b0 or 32]
					type: type?/word data: arg
				][
					b0: find* class-id type
					unless b0 [print "BER encoding error: unsupported type!"]
					b0: any [all [b0/4 = 'yes b0/2 or 32] b0/2]
				]
			]
			switch type [
				logic!		[b1: encode-len data: pick [#{FF} #{00}] data]
				integer!	[b1: encode-len data: int-to-hex data]
				email!		[b1: encode-len data: int-to-hex load to-string head remove back tail data]
				string!		[b1: encode-len data]
				binary! 	[b1: encode-len data]
				none!		[b1: #"^(00)" data: ""]
				block!		[set [b1 data] encode-seq data]
				paren!		[set [b1 data] encode-seq data]
				word!		[
					b0: 96 + select apps data
					set [b1 data] encode-seq list
				]
			]
			head insert out reduce [to char! b0 b1 data]
		]
	]
	
	;--- LDAP protocol definition ---

	scheme: 'LDAP
    port-id: 389
	port-flags: system/standard/port-flags/pass-thru or 32 ; /binary

	fast-query: none
	seq-id: 0

	net-log: get in net-utils 'net-log	
	
	throws: [closed "closed"]
	
;------ Internals --------

	defs: [
		apps [
		;-- Name	 Request  Response
	
			Bind		0		1
			Unbind 		2		none
			Search 		3		4
			Modify 		6		7
			Add 		8		9
			Del 		10		11
			ModifyRDN	12		13
			Compare		14		15
			Abandon 	16		none
			Result		none	5
		]
		filters [
			all any not = in >= <= present like
		]
		error-codes [
			1	"operations error"
			2	"protocol error"
			3	"time limit exceeded"
			4	"size limit exceeded"
			5	"compare false"
			6	"compare true"
			7	"auth method not supported"
			8	"strong auth required"
			16	"no such attribute"
			17	"undefined attribute type"
			18	"inappropriate matching"
			19	"constraint violation"
			20	"attribute or value exists"
			21	"invalid attribute syntax"
			32	"no such object"
			33	"alias problem"
			34	"invalid DN syntax"
			35	"is leaf"
			36	"alias dereferencing problem"
			48	"inappropriate authentication"
			49	"invalid credentials"
			50	"insufficient accessRights"
			51	"busy"
			52	"unavailable"
			53	"unwilling to perform"
			54	"loop detect"
			64	"naming violation"
			65	"object class violation"
			66	"not allowed on non leaf"
			67	"not allowed on RDN"
			68	"entry already exists"
			69	"object class mods prohibited"
			80	"not referenced problem"
		]
	]

	locals-class: context [
	;--- Internals (do not touch!)---
		buf-size: 64 * 1024
		state:
		last-status:
		stream-end?:
		buffer:
		cancel-key: none
	;-------
		protocol: 3
		last-notice:
		error-code:
		error-msg: none
	]

;------ Type Conversion ------
	
	enum-to-int: func [value [email!]][to integer! value/user]
	
	format-object: func [data][
		out: make block! 8
		repend out [to set-word! 'dn data/3/1]
		foreach item data/3/2 [
			insert tail out to set-word! item/1			
			either 1 < length? item/2 [
				insert/only tail out to block! item/2
			][insert tail out item/2]
		]
		make object! out
	]
	
;------ Parsing rules ------

	out: ldapdn: blk: value: op: name: value: tmp: filter: opt-list: err: none 
	
	attr-symbol: [word! | string!]
	
	filter-expr: [
		err:
		'match 
		  set name attr-symbol (clear opt-list: [])
		  1 3 [
		  	['head (op: <0>) | 'center (op: <1>) | 'tail (op: <2>)]
		  	(append opt-list op)
		  ] (repend blk [<4> reduce [name opt-list]])
		  
		| 'present set name attr-symbol 
		  (repend blk [<7> reduce [form name]])
		  
		| set name attr-symbol 
		  ['= (op: <3>) | lesser (op: <5>) | greater (op: <6>) | 'like (op: <8>)]
		  set value [string! | number!]
		  (repend blk [op reduce [form name value]])
	]

	change at filter-expr/21 4 to-lit-word "<="
	change at filter-expr/21 7 to-lit-word ">="

	filter-rule: [
		err:
		['all (op: <0>) | 'any (op: <1>) | 'not (op: <2>)]
		(
			repend blk [op copy* []]
			blk: last tmp: blk
		)
		into [
			some [filter-expr | filter-rule (blk: tail tmp)]
		]
		| filter-expr
	]

	find-rule: [
		err: 
		'filter filter-rule opt [
			'only set value [string! | block!] (append out/2/9 value)
		]
		| 'scope (value: 2@) ['base (value: 0@) | 'one (value: 1@)]
		  (change at out/2 2 value)
		| 'deref (value: 0@) [
			'search		(value: 1@) 
			| 'find		(value: 2@)
			| 'always	(value: 3@)
		  ] (change at out/2 3 value)
		| 'max-size set value integer! (change at out/2 4 value)
		| 'max-time set value integer! (change at out/2 5 value)
		| 'only-attributes (change at out/2 6 true)
		| set value string! (change out/2 value)

	]

	build-search: func [data [block!] /local filter][
		out: copy/deep compose/deep [
			search ["" 2@ 0@ 0 15 (no) <0> [] []]		; default values
		]
		filter: blk: make block! 1		
		unless parse data [some find-rule][
			make error! join "invalid syntax at: " copy/part err 20
		]
		change at out/2 7 reduce [filter/1 filter/2]		
		out
	]

;------ Data reading ------
					
	read: func [[throw] port [port!] len [integer!]][
		pl: port/locals
		if -1 = len: read-io port/sub-port pl/buffer len [
			close* port/sub-port
			throw throws/closed
		]
		if positive? len [net-log ["low level read of " len "bytes"]]
		if negative? len [throw "IO error"]
		len
    ]
    
	defrag-read: func [port [port!] acc-expected [integer!] /local len][
		while [acc-expected > len: length? port/locals/buffer][
			read port acc-expected - len
		]
	]
	
	read-message: func [port [port!] /local len b1 offset][
		pl: port/locals
		
		clear pl/buffer
		defrag-read port 2
		b1: to integer! pl/buffer/2
		;len: (to integer! pl/buffer/2) - 128
		
		either b1 < 128 [
			defrag-read port b1 + 2
		][
			defrag-read port offset: (b1 - 128) + 2
			len: to integer! trim/head copy*/part skip pl/buffer 2 b1 - 128
			defrag-read port len + offset
		]
		BER/decode pl/buffer
	]

	check-error?: func [msg /local code][
		if all [email? msg/3/1 msg/3/1 <> 0@][
			code: to-integer head remove back tail msg/3/1		
			make error! rejoin [
				"LDAP error " code " : " select defs/error-codes code
				any [
					all [not empty? msg/3/3 msg/3/3]
					all [block? pick msg/3 5 msg/3/5/1]
					""
				]
			]
		]
	]

;------ Data sending ------

	write-int32: func [value [integer!]][to string! debase/base to-hex value 16]

	send-packet: func [port [port!] data [binary!]][
		write-io port/sub-port data length? data
		;port/locals/stream-end?: false
	]
	
	insert-query: func [port [port!] data [binary!]][
		send-packet port rejoin ["Q" data #"^@"]
		port/locals/state: 'query-sent
		read-stream/wait port 'fields-fetched
		none
	]
	
	try-reconnect: func [port [port!]][
		net-log "Connection closed by server! Reconnecting..."
		if throws/closed = catch [open port][net-error "Server down!"]
	]
	
	emit-message: func [port data [block!]][
		seq-id: seq-id + 1
		send-packet port BER/encode append reduce [seq-id] data
		seq-id
	]

	do-handshake: func [port [port!] /local pl id][
		pl: port/locals: make locals-class []
		pl/buffer: make binary! pl/buf-size
		id: emit-message port compose/deep [bind [(pl/protocol) "" <0> ""]]
		until [
			res: read-message port
			res/1 = id
		]
		unless zero? enum-to-int res/3/1 [
			close* port/sub-port
			make error! res/3/2
		]			
		net-log "Connected to server. Handshake OK"
	]

;------ Public interface ------

    init: func [port [port!] spec /local scheme args][
        if url? spec [net-utils/url-parser/parse-url port spec]
        fast-query: either all [
        	port/target
        	args: find* port/target #"?" 
        ][
			port/target: copy*/part port/target args
			dehex copy* next args
		][none]
        scheme: port/scheme 
        port/url: spec 
        unless port/host [
            net-error reform ["No network server for" scheme "is specified"]
        ] 
        unless port/port-id [
            net-error reform ["No port address for" scheme "is specified"]
        ]
        unless port/user [port/user: make string! 0]
        unless port/pass [port/pass: make string! 0]
        if port/pass = "?" [port/pass: ask/hide "Password: "]
    ]
    
    open: func [port [port!]][
        open-proto port   
        port/sub-port/state/flags: 524835 ; force /direct/binary mode
        do-handshake port
        ;port/locals/stream-end?: true	; force stream-end, so 'copy won't timeout !
        if fast-query [
        	insert port fast-query
        	fast-query: none
        ]
        port/state/tail: 10		; for 'pick to work properly
    ]
    
    close: func [port [port!]][
    	port/sub-port/timeout: 4
    	either error? try [
    		emit-message port compose/deep [unbind [(none)]]
    	][net-log "Error on closing port!"][net-log "Close ok."]
        close* port/sub-port
    ]
	
	find: func [port [port!] data /local id msg res][
		id: emit-message port build-search data
		res: make block! 1
		until [
			msg: read-message port
			if any [empty? msg msg/1 <> id][
				make error! "Protocol: not matching message ID!"
			]
			if msg/2 = 'search [append res format-object msg]
			msg/2 = 'result
		]
		check-error? msg
		either empty? res [none][res]
	]
	
	; setup BER object apps list
	BER/apps: defs/apps
	
	;--- Register ourselves. 
	net-utils/net-install LDAP self 389
]