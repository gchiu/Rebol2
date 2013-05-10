REBOL [
	Title:  "REBOL Protocols: HTTP"
	Version: 2.7.6
	Rights: "Copyright REBOL Technologies 2008. All rights reserved."
	Home: http://www.rebol.com
	Date: 14-Mar-2008
 
	; You are free to use, modify, and distribute this file as long as the
	; above header, copyright, and this entire comment remains intact.
	; This software is provided "as is" without warranties of any kind.
	; In no event shall REBOL Technologies or source contributors be liable
	; for any damages of any kind, even if advised of the possibility of such
	; damage. See license for more information.
 
	; Please help us to improve this software by contributing changes and
	; fixes. See http://www.rebol.com/support.html for details.
]
 
; I've made some changes to the create-request function to allow http PUT and GET with cookie support.
; 
; Eg.
; 
; read/custom URL [ put %file [ Cookie: "authtoken=foo" ]] will upload a file to URL and also send the cookie header.
; 
; read/custom URL [ put "some text" ] will PUT the "some text" to the URL
; 
; read/custom URL [ get "" [ Cookie: "authtoken=anotherfoo" ]] will read the page at URL while sending the cookie header.
; 
; NB: Rebol2's existing prot-http currently supports this undocumented method using a 'header keyword
; 
; read URL [ header [ Cookie: "authtoken=anotherfoo" ]]
; 
; read/custom URL reduce [ 'soap payload [soapaction: "" ]] will send the SOAP payload to the URL
; 
; Graham
; 
; 7-Aug-2009
; 
; added HEAD support
; 
; read/custom URL [ HEAD "" ]
 
make Root-Protocol [
	"The HTTP protocol."
	open: func [
		port "the port to open"
		/local http-packet http-command response-actions success error response-line
		target headers http-version post-data result generic-proxy? sub-protocol
		build-port send-and-check create-request line continue-post
		tunnel-actions tunnel-success response-code forward proxyauth
	][
		; RAMBO #4039: moved QUERYING to locals
		; also now QUERY will initialize port/locals
		unless port/locals [port/locals: make object! [list: copy [] headers: none querying: no]]
		generic-proxy?: all [port/proxy/type = 'generic not none? port/proxy/host]
 
		build-port: func [] [
			sub-protocol: either port/scheme = 'https ['ssl] ['tcp]
			open-proto/sub-protocol/generic port sub-protocol
			port/url: rejoin [lowercase to-string port/scheme "://" port/host either port/port-id <> 80 [join #":" port/port-id] [copy ""] slash]
			if found? port/path [append port/url port/path]
			if found? port/target [append port/url port/target]
			if sub-protocol = 'ssl [
				if generic-proxy? [
					HTTP-Get-Header: make object! [
						Host: join port/host any [all [port/port-id (port/port-id <> 80) join #":" port/port-id] #]
					]
					user: get in port/proxy 'user
					pass: get in port/proxy 'pass
					if string? :user [
						HTTP-Get-Header: make HTTP-Get-Header [
							Proxy-Authorization: join "Basic " enbase join user [#":" pass]
						]
					]
					http-packet: reform ["CONNECT" HTTP-Get-Header/Host "HTTP/1.1^/"]
					append http-packet net-utils/export HTTP-Get-Header
					append http-packet "^/"
					net-utils/net-log http-packet
					insert port/sub-port http-packet
					continue-post/tunnel
				]
				system/words/set-modes port/sub-port [secure: true]
			]
		]
 
		; smarter query
		http-command: either port/locals/querying ["HEAD"] ["GET"]
		create-request: func [/local target user pass u data ] [
			HTTP-Get-Header: make object! [
				Accept: "*/*"
				Connection: "close"
				User-Agent: get in get in system/schemes port/scheme 'user-agent
				Host: join port/host any [all [port/port-id (port/port-id <> 80) join #":" port/port-id] #]
			]
 
			if all [block? port/state/custom post-data: select port/state/custom 'header block? post-data] [
				HTTP-Get-Header: make HTTP-Get-Header post-data
			]
 
			HTTP-Header: make object! [
				Date: Server: Last-Modified: Accept-Ranges: Content-Encoding: Content-Type:
				Content-Length: Location: Expires: Referer: Connection: Authorization: none
			]
 
			http-version: "HTTP/1.0^/"
			all [port/user port/pass HTTP-Get-Header: make HTTP-Get-Header [Authorization: join "Basic " enbase join port/user [#":" port/pass]]]
			user: get in port/proxy 'user
			pass: get in port/proxy 'pass
			if all [generic-proxy? string? :user] [
				HTTP-Get-Header: make HTTP-Get-Header [
					Proxy-Authorization: join "Basic " enbase join user [#":" pass]
				]
			]
			; range request
			if port/state/index > 0 [
				http-version: "HTTP/1.1^/"
				HTTP-Get-Header: make HTTP-Get-Header [
					Range: rejoin ["bytes=" port/state/index "-"]
				]
			]
			target: next mold to-file join (join "/" either found? port/path [port/path] [""]) either found? port/target [port/target] [""]
 
			post-data: none
 
comment { ; original code			
			if all [block? port/state/custom post-data: find port/state/custom 'post post-data/2] [
				http-command: "POST"
				HTTP-Get-Header: make HTTP-Get-Header append [
					Referer: either find port/url #"?" [head clear find copy port/url #"?"] [port/url]
					Content-Type: "application/x-www-form-urlencoded"
					Content-Length: length? post-data/2
				] either block? post-data/3 [post-data/3] [[]]
				post-data: post-data/2
			]
}
; start Graham's changes
			either all [block? port/state/custom post-data: find port/state/custom 'post post-data/2] [
				http-command: "POST"
				HTTP-Get-Header: make HTTP-Get-Header append [
					Referer: either find port/url #"?" [head clear find copy port/url #"?"] [port/url]
					Content-Type: "application/x-www-form-urlencoded"
					Content-Length: length? post-data/2
				] either block? post-data/3 [post-data/3] [[]]
				post-data: post-data/2
			][
				either all [
					block? port/state/custom 
					any [
						post-data: find port/state/custom to-word http-command: "GET" 
						post-data: find port/state/custom to-word http-command: "HEAD" 
					]
					post-data/2
				] [
					HTTP-Get-Header: make HTTP-Get-Header append [
						Referer: either find port/url #"?" [head clear find copy port/url #"?"] [port/url]
					] either block? post-data/3 [post-data/3] [[]]
					post-data: none
				][
					either all [block? port/state/custom post-data: find port/state/custom 'put post-data/2] [
						http-command: "PUT"
						data: either file? post-data/2 [
							system/words/read/binary post-data/2
						][
							post-data/2
						]
						HTTP-Get-Header: make HTTP-Get-Header append [
							Content-Type: "application/octet-stream"
							Content-Length: length? data
						] either block? post-data/3 [post-data/3] [[]]
						post-data: data
					][
						either all [block? port/state/custom post-data: find port/state/custom 'soap post-data/2] [
							http-command: "POST"
							data: either file? post-data/2 [
								system/words/read/binary post-data/2
							][
								post-data/2
							]
							HTTP-Get-Header: make HTTP-Get-Header append [
								Content-Type: {text/xml; charset="utf-8"}
								Content-Length: length? data
							] either block? post-data/3 [post-data/3] [[]]
							post-data: data
						][
							if all [block? port/state/custom post-data: find port/state/custom 'delete post-data/2] [
								http-command: "DELETE"
								HTTP-Get-Header: make HTTP-Get-Header append [
									Referer: either find port/url #"?" [head clear find copy port/url #"?"] [port/url]
								] either block? post-data/3 [post-data/3] [[]]
								post-data: none
							]
						]
					]
				]
			]
; end changes from Graham
 
			http-packet: reform [http-command either generic-proxy? [port/url] [target] http-version]
			append http-packet net-utils/export HTTP-Get-Header
;			append http-packet "^/"
;			if post-data [append http-packet post-data]
		]
 
		send-and-check: func [] [
			net-utils/net-log http-packet
 
			; Sterling, why was this changed from insert to write-io ? It causes HTTP to be sent
			; without cr and breaks things.
			; write-io port/sub-port http-packet length? http-packet
			insert port/sub-port http-packet
; Begin Max's patch
; This lets more than 16K be sent as post data when using https.
;-- old
;			if post-data [
;				write-io port/sub-port post-data length? post-data
;			]
;-- new
            if post-data [
                ptr: post-data
                until [
                    data: copy/part ptr 8192
                    ptr: skip ptr 8192
                    write-io port/sub-port data length? data
                    tail? ptr
                ]
            ]			
			continue-post
		]
; End Max's patch 
		continue-post: func [/tunnel /local digit space] [
			response-line: system/words/pick port/sub-port 1
			net-utils/net-log response-line
			either none? response-line [do error][
				; fixes #3494: should accept an HTTP/0.9 simple response.
				digit: charset "1234567890"
				space: charset " ^-"
				either parse/all response-line [
					; relaxing rule a bit
					;"HTTP/" digit "." digit some space copy response-code 3 digit some space to end
					"HTTP/" digit "." digit some space copy response-code 3 digit to end
				] [
					; valid status line
					response-code: to integer! response-code
					result: select either tunnel [tunnel-actions] [response-actions] response-code
					either none? result [do error] [do get result]
				] [
					; could not parse status line, assuming HTTP/0.9
					port/status: 'file
				]
			]
		]
 
		tunnel-actions: [
			200	   tunnel-success ; Tunnel established
		]
 
		response-actions: [
			100    continue-post  ; HTTP/1.1 continue with posting data
			200    success   ; standard valid response
			201    success   ; post command successful - new url included
			204    success   ; no new content (maybe use :true here?)
			206    success   ; read partial content
			300    forward   ; multiple choices of locations in the body - maybe preferred in Location:
			301    forward   ; moved permanently - Location: hold new loc
			302    forward   ; moved temporarily - Location: hold new loc
			304    success   ; not modified since the If-Modified-Since header date
			307    forward   ; temporary redirect
			407    proxyauth ; requires proxy authorization
		]
 
		tunnel-success: [
			while [ ( line: pick port/sub-port 1 ) <> "" ] [net-utils/net-log line]
		]
 
		success: [
			headers: make string! 500
			while [ ( line: pick port/sub-port 1 ) <> "" ] [append headers join line "^/"] ; remove the headers
			port/locals/headers: headers: Parse-Header HTTP-Header headers
			port/size: 0
			if port/locals/querying [if headers/Content-Length [port/size: load headers/Content-Length]]
			if error? try [port/date: parse-header-date headers/Last-Modified] [port/date: none]
			port/status: 'file
		]
 
		error: [
			system/words/close port/sub-port
			net-error reform ["Error.  Target url:" port/url "could not be retrieved.  Server response:" response-line]
		]
 
		forward: [
			page: copy ""
			while [ ( str: pick port/sub-port 1 ) <> "" ][ append page reduce [str newline] ]
			headers: Parse-Header HTTP-Header page
			insert port/locals/list port/url
			either found? headers/Location [
				either any [find/match headers/Location "http://" find/match headers/Location "https://"] [ ; new whole url to go to
					port/path: port/target: port/port-id: none
					net-utils/URL-Parser/parse-url/set-scheme port to-url port/url: headers/Location
					if not port/port-id: any [port/port-id all [in system/schemes port/scheme get in get in system/schemes port/scheme 'port-id]] [
					net-error reform ["HTTP forwarding error: Scheme" port/scheme "for URL" port/url "not supported in this REBOL."]
					]
				] [
					either (first headers/Location) = slash [port/path: none remove headers/Location] [either port/path [insert port/path "/"] [port/path: copy "/"]]
					port/target: headers/Location
					port/url: rejoin [lowercase to-string port/scheme "://" port/host either port/path [port/path] [""] either port/target [port/target] [""]]
				]
				if find/case port/locals/list port/url [net-error reform ["Error.  Target url:" port/url "could not be retrieved.  Circular forwarding detected"]]
				system/words/close port/sub-port
				build-port
				create-request
				send-and-check
			] [
				do error
			]
		]
 
		proxyauth: [
			system/words/close port/sub-port
			either all [ generic-proxy? (not string? get in port/proxy 'user) ] [
				port/proxy/user: system/schemes/http/proxy/user: port/proxy/user
				port/proxy/pass: system/schemes/http/proxy/pass: port/proxy/pass
				if not error? try [result: get in system/schemes 'https] [
					result/proxy/user: port/proxy/user
					result/proxy/pass: port/proxy/pass
				]
			] [
				net-error reform ["Error. Target url:" port/url "could not be retrieved: Proxy authentication denied"]
			]
			build-port
			create-request
			send-and-check
		]
		build-port
		create-request
		send-and-check
	]
 
	query: func [port] [
		if not port/locals [
			; RAMBO #4039: query mode is local to port now
			port/locals: make object! [list: copy [] headers: none querying: yes]
			open port
			; port was kept open after query
			; attempt for extra safety
			; also note, local close on purpose
			attempt [close port]
			; RAMBO #3718 - superceded by fix for #4039
			;querying: false
		]
		none
	]
 
	close: func [port] [system/words/close port/sub-port]
 
	net-utils/net-install HTTP self 80
	system/schemes/http: make system/schemes/http [user-agent: reform ["REBOL" system/product system/version]]
	
	net-utils/net-install HTTPS self 443
	system/schemes/https: make system/schemes/https [user-agent: reform ["REBOL" system/product system/version]]
]