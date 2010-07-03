REBOL [
	Title: "JDBC Bridge Handler"
	Purpose: "Access to JDBC via bridge"
	Author: "Graham Chiu"
	File: %prot-jdbcbridge.r
	Date: 2010-07-03
	Version: 0.0.1
	Copyright: "Graham Chiu"
	License: "Lesser GNU General Public License (LGPL)"
	History: [ 
		3-July-2010 first pass
	]
	Library: [
		level: 'intermediate
		platform: [Linux Windows]
		type: [protocol tool]
		domain: [protocol database]
		tested-under: [
			2.7.6.3.1
		]
		support: none
		license: 'LGPL
	]
]

make root-protocol [
	scheme: 'jdbcbridge
	port-id: 8000
	port-flags: system/standard/port-flags/pass-thru
	awake: none
	open-check: none
	buffer: ""
	crlfbin: to-binary crlf
	
	sys-copy: get in system/words 'copy
	sys-insert: get in system/words 'insert
	sys-pick: get in system/words 'pick
	sys-close: get in system/words 'close
	sys-write: get in system/words 'write
	sys-length?: get in system/words 'length?
	net-log: get in net-utils 'net-log	

	init: func [[catch] port spec] [
	        if not url? spec [net-error "Bad URL"]
		net-utils/url-parser/parse-url port spec
		; if none? port/target [net-error reform ["No database name for" port/scheme "is specified"]]

		port/locals: make object! [columns: none rows: 0 values: none  index: 0]
		port/url: spec 
	]

	open: func [port [port!]][
		; open the subport
		open-proto port
		port/state/index: 0
		port/state/tail: 65535
		print ["port/path = " port/path]
		print ["port/target = " port/target]
		port/state/flags: port/state/flags or port-flags
	]

	close: func [port [port!]][
		write-io port/sub-port join "QUIT" crlf 6
		sys-close port/sub-port
	]

	insert: func [ port cmd [string! block!] /local data ] [
		either string? cmd [
			write-io port/sub-port data: join cmd crlf sys-length? data
		][
			either any [word? cmd/1 lit-word? cmd/1] [
				net-log form reduce cmd
				write-io port/sub-port data: join form reduce cmd crlf sys-length? data
			] [
				; replace the place holders
				foreach var next cmd [
					either any [string? var date? var] [
						replace cmd/1 "(?)" rejoin ["'" var "'"]
					] [
						replace cmd/1 "(?)" var
					]
				]
				write-io port/sub-port data: join cmd/1 crlf sys-length? data
			]
		]
		buffer: load sys-pick port/sub-port 1
		if not zero? port/locals/rows: sys-length? buffer [
			port/locals/columns: sys-length? buffer/1
		]
	]	
	
	copy: func [ port /local data] [
		; buffer: sys-copy to-string (sys-copy port/sub-port)
		data: sys-copy buffer
		buffer: sys-copy ""
		port/locals: make object! [columns: none rows: 0 values: none  index: 0]
		data
	]
	
	pick: func [ port n /local data ][
		either all [ n > 0 n <= port/locals/rows ][
			data: sys-pick buffer n
			remove skip buffer n - 1
			port/locals/rows: sys-length? buffer
			data
		][
			none
		]
	]
	
	net-utils/net-install :scheme self :port-id
]

comment {
	same syntax as the ODBC drivers
	supports only 'columns and 'tables for metadata, and only partially so
}

