REBOL [
	Title: "atcp:// protocol (Asynchronous TCP)"
	Purpose: {
		A protocol handler (atcp://) to do asynchronous I/O with TCP.
	}
	Author: "Romano Paolo Tenca"
	File: %atcp-protocol.r
	License: {
Copyright (C) 2003-2005 Romano Paolo Tenca
All rights reserved.

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.

http://www.gnu.org/copyleft/gpl.html
}
	Date: 01/10/2005
	Version: 0.2.2
	Note: {}
	history: [
		0.2.2 01/10/2005 {
			Fixed the tail problem in read
			Rebol do not set the index at the right	position in the data buffer
			(this can or cannot be a bug of Rebol -- this detail is	undocumented).
		}
		0.2.1 26/07/2004 "First public beta release"
	]
	Todo: {
		- Check the race condition reported by Ladislav: read (or write?) event after
          that the user closed the port.
		  A solution: do not generate close event after the user close the Atcp port.
		  A suggestion: when the user close the ATCP port, the user must remove the port
		  by the wait-list before Wait is called again.
		  Question: can the race event be generated in the same Wait session in which the
		  user closed the port from async event handling code?
	}
]
async-utils: context [
	closure: func [port][use [async][async: port make function! [] [async]]]
	system/words/real-error?:
	real-error?: func [err [error!]][517 <> get in disarm :err 'code]
	system/words/to-async:
	to-async: func [
		port "Connected tcp port or open listen port"
		/awake "The awake to add" af [block! function!]
	][
		either none? port/host [
			port/async-modes: 'accept
			all [
				awake
				port/awake: either function? :af [:af][make function! [port] af]
			]
			port
	][
			either awake [
				open/custom make port! [scheme: 'atcp sub-port: port] reduce ['awake :af]
			][
				open make port! [scheme: 'atcp sub-port: port]
			]
		]
	]
	set-main-sub-port: func [main async][
		main/sub-port: async/sub-port
		async/sub-port: none
		main/sub-port/user-data: closure main
		close async
	]
	sw4: func [
		"sw4 handling"
		port data event
		/local buffer
	][
		switch/default event [
			connect [
				write-io port buffer: rejoin [
					#{0401}
					to-char data/main-port/port-id / 256
					to-char data/main-port/port-id // 256
					to-binary data/ip
					to-char 0
				] length? buffer
				false
			]
			read [
				read-io port buffer: make binary! 8 8
				either 90 <> pick buffer 2 [
					call-continue data make error! reform [
						"Connection to" data/main-port/host "failed"
					]
				][
					set-main-sub-port data/main-port port
					call-continue data 'connect
				]
			]
		][false]
	]
	sw5: func [
		"sw5 handling"
		port data event
		/local host buffer write-host-port readn writeb remote-ip remote-port
	][
		readn: func [n [integer!]][read-io port buffer: make binary! n n]
		writeb: func [value][write-io port value length? value]
		write-host-port: [
			host: form data/main-port/host
			writeb rejoin [
				#{05}
				to-char pick [2 1] data/mode = 'bind
				#{0003}
				to-char length? host
				host
				to-char data/main-port/port-id / 256
				to-char data/main-port/port-id // 256
			]
			data/state: 3
			false
		]
		switch/default event [
			connect [
				writeb #{05020002}
				false
			]
			read [
				do pick [
					[
						readn 2
						either 255 = pick buffer 2 [
							call-continue data make error! "Failed proxy handshake"
						][
							either 0 = second buffer write-host-port [
								writeb rejoin [
									to-char 1
									to-char length? port/user
									port/user
									to-char length? port/pass
									port/pass
								]
								data/state: 2
								false
							]
						]
					]
					[
						readn 2
						either 0 = pick buffer 2 write-host-port [
							call-continue data make error! "Failed proxy user authentication"
						]
					]
					[
						readn 10
						either 0 <> pick buffer 2 [
							call-continue data make error! reform [
								"Connection to" data/main-port/host "failed"
							]
						][
							either data/mode = 'bind [
								buffer: at buffer 5
								data/main-port/sub-port/host: port/sub-port/host: to-tuple copy/part buffer 4
								data/main-port/sub-port/port-id: port/sub-port/port-id: buffer/5 * 256 + buffer/6
								data/state: 4
								call-continue data 'bind
							][
								set-main-sub-port data/main-port port
								call-continue data 'connect
							]
						]
					]
					[
						readn 10
						either parse/all/case buffer [
							#{0500} 2 skip copy remote-ip 4 skip copy remote-port 2 skip
						][
							port/sub-port/remote-port: 256 * (to-integer remote-port/1) + remote-port/2
							port/sub-port/remote-ip: to-tuple to-binary remote-ip
							set-main-sub-port data/main-port port
							call-continue data 'connect
						][
							call-continue port make error! join "Invalid accept string: {" [mold buffer "}"]
						]
					]
				] data/state
			]
		][false]
	]
	proxy-detect: func [
		{The awake routine of the async port connected with the proxy}
		port
		event [word! error!]
		/local data
	][
		data: port/user-data
		either error? event [
			call-continue data event
		][
			switch/default event [
				dns-failure [call-continue data make error! "Can't find proxy ip"]
				max-retry [call-continue data make error! "Can't connect to proxy"]
				close [call-continue data make error! "Failed proxy handshake"]
			][
				either 'socks4 = data/type [
					sw4 port data event
				][
					sw5 port data event
				]
			]
		]
	]
	open-proxy: func [
		"Open an async tcp port toward the proxy"
		port data
	][
		system/words/open/binary/custom port/sub-port: make port! [
			scheme: 'atcp
			host: port/proxy/host
			user: get in port/proxy 'user
			pass: get in port/proxy 'pass
			port-id: port/proxy/port-id
			proxy: make proxy [host: user: pass: type: none]
			user-data: data
		] reduce ['detect :proxy-detect]
	]
	call-continue: func [
		[catch]
		{Call the continue with user-data and result (can be an error)}
		data result [error! word!]
	][
		data/continue data/main-port select data 'continue-data :result
	]
	async-connect-proxy: func [
		{Open an async tcp binary connection using proxy (socks socks4 socks5)}
		port "Port to connect"
		mode
		continue-data {Data passed to the continue function (do not use func! or set-word!)}
		continue [function!] {User function to call for an event (args: port data event)}
		/local data
	][
		data: reduce [
			'main-port port
			'state 1
			'ip none
			'type port/proxy/type
			'mode mode
			'continue :continue
			'continue-data :continue-data
		]
		either any [
			data/type <> 'socks4
			not error? try [data/ip: to-tuple port/host]
		][
			open-proxy port data
		][
			insert port/sub-port: system/words/open/no-wait [
				scheme: 'dns
				host: "/async"
				user-data: data
				awake: func [port /local data][
					data: port/user-data
					either none? data/ip: copy port [
						call-continue data make error! "Can't resolve the host name"
					][
						close port
						open-proxy data/main-port data
						false
					]
				]
			] port/host
		]
	]
	async-protocols: [atcp:// assl:// atls://]
	make-async-protocol: func [name [word!] port-id [integer!] spec [block! object!] /bind][
		if block? spec [
			all [bind spec: system/words/bind spec 'self]
			spec: make async-root-protocol spec
		]
		do reduce ['net-utils/net-install name spec port-id]
		insert tail async-protocols join name "://"
		async-protocols: unique async-protocols
		spec
	]
	system/words/open-async:
	open-async: func [
		[catch]
		"Opens and allocate an async port"
		spec [url!]
		awake [block! function! none!]
		/binary "Preserves contents exactly."
		/string "Translates all line terminators."
		/lines "Handles data as lines."
		/direct "Opens the port without buffering."
		/read "Read only. Disables write operations."
		/write "Write only.  Disables read operations."
		/with "Specifies alternate line termination."   end-of-line [char! string!]
		/custom "Allows special refinements." params [block!]
		/detect det [block! function!]
		/skip "Skips a number of bytes." length [number!]
		/local par cus
	][
		any [
			foreach x async-protocols [
				if find/match spec x [break]
				if find/match spec next x [
					insert spec: copy spec #"a"
					break
				]
			]
			throw make error! "Unsupported async scheme"
		]
		args: copy []
		params: copy any [params []]
		all [:awake insert/only insert tail params 'awake :awake]
		all [:detect insert/only insert tail params 'detect :det]
		foreach arg [binary string lines read write direct][
			all [get arg insert tail args arg]
		]
		code: copy/deep [open/mode/custom spec args params]
		all [skip insert tail code/1 'skip insert tail code length]
		all [with insert tail code/1 'with insert tail code end-of-line]
		do code
	]
	sopen: :open
	sclose: :close
	sget-modes: :get-modes
	sset-modes: :set-modes
	digit: charset "0123456789"
	line-len: func [data][
		-1 + max index? any [find/last/tail data cr data] index? any [find/last/tail data lf data]
	]
	rejoin-ports: func [async sub-port awake][
		sub-port/user: async/user
		sub-port/pass: async/pass
		sub-port/path: async/path
		sub-port/target: async/target
		sub-port/user-data: closure async
		sub-port/awake: :awake
		sub-port/async-modes: copy either empty? async/locals/outbuffer [[read]][[read write]]
	]
	set 'async-root-protocol make root-protocol [
		default-detect: func [port event [error! word!]][true]
		notify: func [async event [word! error!]][
			insert tail async/locals/events :event
			async/locals/detect async :event
		]
		awake: func [port][none]
		get-sub-port: func [
			port "An open port spec"
			/local err
		][
			clear port/locals/events
			either port/sub-port [
				any [
					port/sub-port/async-modes <> 'connect
					error? port/locals/connect-result: try [
						sopen/binary/direct/no-wait port/sub-port
					]
					port/locals/connect-result: 'success
				]
				port/sub-port
			][
				false
			]
		]
		init: func [
			"Parse URL and/or check the port spec object"
			port "Unopened port spec"
			spec {Argument passed to open or make (a URL or port-spec)}
			/local tdig num
		][
			port/state/with: copy "^M^/"
			if not port? port/sub-port [
				if url? spec [net-utils/url-parser/parse-url port spec]
				if none? port/host [
					net-error reform ["No network server for" port/scheme "is specified"]
				]
				if none? port/port-id [
					net-error reform ["No port address for" port/scheme "is specified"]
				]
				spec: copy []
				tdig: [copy num 1 3 digit (num: to integer! num if num < 256 [insert tail spec num])]
				all [
					parse to string! port/host [
						any #" " 3 [tdig #"."] tdig end (
							spec: either 4 = length? spec [to tuple! spec][none]
						)
					]
					spec
					port/host: spec
				]
			]
		]
		open-proto-sub: func [
			"Open the socket connection handling proxy"
			port "Initalized port spec"
			ip
			/local sub-port data in-bypass find-bypass bp subproto secure generic err
		][
			subproto: port/locals/subproto
			secure: port/locals/secure
			net-utils/net-log reform ["Opening async" to-string subproto "for" to-string port/scheme]
			if not system/options/quiet [print ["Initialize connection to:" port/host]]
			find-bypass: func [host ip bypass /local x][
				foreach item bypass [
					if any [
						all [x: find/match/any host item tail? x]
						all [x: find/match/any ip item tail? x]
					][return true]
				]
				false
			]
			in-bypass: func [host ip bypass][
				if any [none? bypass empty? bypass none? host][return false]
				find-bypass form host form ip bypass
			]
			either all [
				port/proxy/host
				bp: not in-bypass port/host ip port/proxy/bypass
				find [socks4 socks5 socks] port/proxy/type
			][
				async-connect-proxy port 'connect reduce [
					all [secure find [ssl tls] subproto]
					subproto
				] func [
					port data event [error! word!]
				][
					either error? event [
						sclose port/sub-port
						port/sub-port: none
						notify port event
					][
						if net-watch [
							print rejoin ["Connected to: " port/host ":" port/port-id " proxy: " port/sub-port/scheme " " port/sub-port/host ":" port/sub-port/port-id]
						]
						if pick data 1 [
							sset-modes port/sub-port [async-modes: none]
							sset-modes port/sub-port [secure: true]
						]
						rejoin-ports port port/sub-port :tcp-awake
						notify port 'connect
					]
				]
				false
			][
				generic: all [port/proxy/type = 'generic port/locals/generic bp]
				either error? err: try [
					port/sub-port: make port! compose [
						scheme: (to-lit-word subproto)
						host: either generic [port/proxy/host][
							port/proxy/host: none
							ip
						]
						user: port/user
						pass: port/pass
						timeout: port/timeout
						port-id: either generic [port/proxy/port-id][port/port-id]
						awake: :tcp-awake
						async-modes: 'connect
						user-data: closure port
					]
				][
					notify port err
				][
					false
				]
			]
		]
		port-flags: system/standard/port-flags/direct
		open-proto: func [
			{Initiate the connection, locals/detect will be called when estabilished.}
			port "Initalized port spec"
			/sub-protocol subproto
			/secure
			/generic
			/detect proto-detect [function!]
			/local tmp user-detect locals custom
		][
			net-utils/net-log reform ["Opening" port/scheme "connection"]
			custom: any [port/state/custom []]
			locals: port/locals: make either port/locals [port/locals][object!][
				conn-state: 0
				max-retry: any [select custom 'max-retry 2]
				retry: 0
				peer-close: false
				events: copy []
				detect: :default-detect
				user-detect: any [
					all [
						tmp: select custom 'detect
						either function? :tmp [:tmp][func [port event [word! error!]] tmp]
					]
					:default-detect
				]
				secure: generic: subproto: none
				modes: make object! sget-modes port [lines binary]
				connect-result: none
				transfer-size: any [select custom 'transfer-size 4 * 1024]
				outbuffer: make string! transfer-size + 2
				inbuffer: make string! transfer-size + 2
				data: make string! transfer-size + 2
			]
			either detect [
				port/locals/detect: :proto-detect
			][
				port/locals/detect: get in port/locals 'user-detect
				port/locals/user-detect: none
			]
			all [
				tmp: select custom 'awake
				port/awake: either function? :tmp [:tmp][func [port] tmp]
			]
			port/locals/subproto: any [subproto 'tcp]
			port/locals/generic: generic
			port/locals/secure: secure
			port/state/flags: port/state/flags or port-flags
			either port? port/sub-port [
				port/sub-port/user-data: closure port
				port/sub-port/async-modes: copy [read]
				port/sub-port/awake: :tcp-awake
			][
				either tuple? port/host [
					open-proto-sub port port/host
				][
					port/sub-port: sopen/no-wait [
						scheme: 'dns
						host: "/async"
						user-data: closure port
						awake: :dns-awake
					]
					insert port/sub-port port/host
				]
			]
		]
		dns-awake: func [dnsport /local async tmp][
			async: dnsport/user-data
			tmp: copy dnsport
			sclose dnsport
			async/sub-port: none
			either tmp [
				open-proto-sub dnsport/user-data tmp
				notify dnsport/user-data 'dns
			][
				notify dnsport/user-data 'dns-failure
			]
		]
		open: func [
			{Open the socket connection and confirm server response.}
			port "Initalized port spec"
		][
			open-proto/generic/sub-protocol port select [atcp tcp assl ssl atls tls] port/scheme
		]
		tcp-awake: func [
			port
			/local data err async locals outbuffer inbuffer read-result write-result result start
		][
			async: port/user-data
			locals: async/locals
			either not none? locals/connect-result [
				error? err: locals/connect-result
				locals/connect-result: none
				either error? err [
					either real-error? err [
						port: async/sub-port: none
						notify async :err
					][
						either all [
							integer? locals/max-retry
							locals/max-retry <= locals/retry: locals/retry + 1
						][
							locals/retry: 0
							notify async 'max-retry
						][false]
					]
				][
					if locals/secure [
						sset-modes port [async-modes: none]
						sset-modes port [secure: true]
					]
					if net-watch [print rejoin ["Connected to: " port/host ":" port/port-id]]
					rejoin-ports async port :tcp-awake
					notify async 'connect
				]
			][
				outbuffer: async/locals/outbuffer
				inbuffer: async/locals/inbuffer
				data: clear locals/data
				if all [block? port/async-modes find port/async-modes 'read][
					either error? err: try [read-io port data locals/transfer-size][
						if real-error? :err [error? read-result: :err]
					][
						start: tail inbuffer
						either err > 0 [
							insert/part start data err
						][
							either err <= -2 [
								net-utils/net-log join "read-io aborted with " err
							][
								locals/peer-close: true
								remove find port/async-modes 'read
								any [empty? inbuffer read-result: 'read]
							]
						]
					]
				]
				if not empty? outbuffer [
					either error? err: try [
						write-io port outbuffer either sget-modes async 'binary [
							min locals/transfer-size length? outbuffer
						][
							length? outbuffer
						]
					][
						if real-error? :err [
							error? write-result: :err
						]
					][
						either err > 0 [
							locals/outbuffer: skip locals/outbuffer err
							if tail? locals/outbuffer [
								locals/outbuffer: clear head locals/outbuffer
								write-result: 'write
								remove find port/async-modes 'write
							]
						][
							either err <= -2 [
								net-utils/net-log join "write-io aborted with " err
							][
								locals/peer-close: true
								remove find port/async-modes 'write
								close-result: 'close
							]
						]
					]
				]
				result: false
				if all [
					not empty? inbuffer
					any [
						not locals/modes/lines
						find inbuffer newline
					]
				][read-result: 'read]
				any [none? read-result result: result or notify async read-result]
				any [none? write-result result: result or notify async write-result]
				if locals/peer-close [result: result or notify async 'close]
				result
			]
		]
		read: func [port data /local locals eol len inbuffer][
			locals: port/locals
			inbuffer: locals/inbuffer
			either any [
				none? port/sub-port
				'dns = port/sub-port/scheme
				port/sub-port/async-modes = 'connect
			][
				-4
			][
				len: min port/state/num either any [
					locals/peer-close
					not sget-modes port 'lines
				][
					length? inbuffer
				][
					eol: line-len inbuffer
				]
				either len = 0 [
					either locals/peer-close [-1][-4]
				][
					insert/part tail data inbuffer len
					remove/part inbuffer len
					len
				]
			]
		]
		write: func [port data /local outbuffer][
			either port/state/num > 0 [
				outbuffer: port/locals/outbuffer
				data: offset? tail outbuffer insert/part tail outbuffer data port/state/num
				any [
					port/sub-port/scheme = 'dns
					port/sub-port/async-modes = 'connect
					port/sub-port/async-modes: copy [read write]
				]
				data
			][0]
		]
		close: func [port][
			if port/sub-port [
				either any [
					port/sub-port/scheme = 'dns
					port/sub-port/async-modes <> 'connect
				][
					sclose port/sub-port
				][
					net-utils/net-log join "tcp sub-port of " [port/host " cannot be closed (connect mode)"]
				]
				port/sub-port: none
			]
		]
		set-modes: func [
			port "An open port spec"
			modes "A mode block"
			/local tmp
		][
			do bind intersect/skip modes third port/locals/modes 2 in port/locals/modes 'self
			if tmp: find modes [async-modes:][port/sub-port/async-modes: second tmp]
		]
		query: func [async /local port][
			port: async/sub-port
			reduce [
				'status any [
					all [none? port 'failure]
					all [port/scheme = 'dns 'dns]
					all [port/scheme = 'tcp port/async-modes]
				]
				'peer-close async/locals/peer-close
				'outbuffer any [
					all [none? async/locals 0]
					length? async/locals/outbuffer
				]
				'inbuffer any [
					all [none? async/locals 0]
					length? async/locals/inbuffer
				]
			]
		]
		net-utils/net-install 'atcp self 0
		if find system/components 'ssl [
			net-utils/net-install 'assl self 0
			net-utils/net-install 'atsl self 0
		]
	]
]
;support global routine
wait-list?: does [system/ports/wait-list]
wait-find: func [port [port!]][find system/ports/wait-list port]
wait-stop: func [port [port!]][remove wait-find port]
wait-start: func [port [port!]][insert tail system/ports/wait-list port]
