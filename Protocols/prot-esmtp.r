REBOL [
	Title:  "REBOL Protocols: ESMTP"
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

make Root-Protocol [
	{Communicate with ESMTP.  This protocol is unusual in that it is
	a write only port.  It is pass-thru and it sends an email at each
	INSERT; you need to insert a block with the from address, the to 
	addresses, and the mail (complete with headers). 
	There is no URL represenation of this entire protocol at this time
	(but there could be).}

	port-flags: system/standard/port-flags/pass-thru

	open-check:  [ none  "220"] ; ["HELO" system/network/host] "250"]
	close-check: ["QUIT" "221"]
	write-check: [ none  "250"]
	data-check:  ["DATA" "354"]

	open: func [
		"Open the socket connection and confirm server response."
		port "Initalized port spec"

		/local tmp auth-key ehlo-response auth-methods
	] [
		open-proto port
		; make the protocol RFC compliant - use EHLO if possible
		ehlo-response: attempt [net-utils/confirm/multiline/all port/sub-port [["EHLO" system/network/host] "250"]]
		either found? ehlo-response [
			auth-methods: make block! 3
			foreach response ehlo-response [
				parse response [
					["250-" | "250"]
					"AUTH" any [
						"CRAM-MD5" (append auth-methods 'cram)
						|
						"PLAIN" (append auth-methods 'plain)
						|
						"LOGIN" (append auth-methods 'login)
						|
						to " "
					]
				]
			]
			net-utils/net-log ["Supported auth methods:" auth-methods]
			; fix: only ask once if the user used set-net ask
			port/user: port/user
			port/pass: port/pass
			; do authn if needed
			if all [found? port/user found? port/pass] [
				case [
					find auth-methods 'cram [
						tmp: net-utils/confirm port/sub-port ["AUTH CRAM-MD5" "334"] 
						parse/all tmp ["334 " copy auth-key to end]
						auth-key: debase auth-key
						; compute challenge response
						auth-key: checksum/method/key auth-key 'md5 port/pass
						; try to authenticate
						net-utils/confirm port/sub-port reduce [
							enbase reform [port/user lowercase enbase/base auth-key 16]
							"235"
						]
					]
					find auth-methods 'plain [
						net-utils/net-log ["WARNING! Using AUTH PLAIN."]
						net-utils/confirm port/sub-port reduce [
							join "AUTH PLAIN " enbase rejoin [port/user #"^@" port/user #"^@" port/pass]
							"235"
						]
					]
					find auth-methods 'login [
						net-utils/net-log ["WARNING! Using AUTH LOGIN."] 
						net-utils/confirm port/sub-port reduce [
							"AUTH LOGIN" "334" 
							enbase port/user "334" 
							enbase port/pass "235"
						]
					]
					true [
						net-utils/net-log ["None of the server's authentication methods are supported. Can't authenticate."]
					]
				]
			] 
		] [
			; only plain SMTP supported - no auth possible
			net-utils/confirm port/sub-port [["HELO" system/network/host] "250"]
		]
	]

	confirm-command: func [
		port
		command
	] [
		net-utils/confirm port/sub-port reduce [rejoin command "250"]
	]

	insert: func [
		"INSERT called on port"
		port "Opened port"
		data
	] [
		if string? data/1 [
			use [ e ][
				either parse/all data/1 [ thru "<" copy e to ">" to end ][
					if error? try [ data/1: to-email e ][
						net-error "ESMTP: invalid from address"
					]
				][ net-error "ESMTP: invalid from address" ]
			]
		]
		if not all [
			block? :data 
			parse data [email! into [some email!] string!]
		][net-error "ESMTP: Invalid command"]
		confirm-command port ["MAIL FROM: <" data/1 ">"]
		foreach addr data/2 [
			confirm-command port ["RCPT TO: <" addr ">"]
		]
		net-utils/confirm port/sub-port data-check
		system/words/insert port/sub-port replace/all copy data/3 "^/." "^/.."
		system/words/insert port/sub-port "."
		net-utils/confirm port/sub-port write-check
	]

	net-utils/net-install ESMTP self 25
]
