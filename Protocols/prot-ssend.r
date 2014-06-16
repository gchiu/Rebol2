REBOL [
	Title:  "REBOL Protocols: Send Email"
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

ssend: func [
	"Send a message to an address (or block of addresses)"
	;Note - will also be used with REBOL protocol later.
	address [email! block!] "An address or block of addresses"
	message "Text of message. First line is subject."
	/only   "Send only one message to multiple addresses"
	/header "Supply your own custom header"
	header-obj [object!] "The header to use"
	/attach "Attach file, files, or [.. [filename data]]"
	files [file! block!] "The files to attach to the message"
	/subject "Set the subject of the message"
	subj "The subject line"
	/show "Show all recipients in the TO field"
	/local smtp-port boundary make-boundary tmp from
][
	make-boundary: does []

	if file? files [files: reduce [files]] ; make it a block
	if email? address [address: reduce [address]] ; make it a block
	message: either string? message [copy message] [mold message]

	if not header [                 ; Clone system default header
		header-obj: make system/standard/email [
			subject: any [subj copy/part message any [find message newline 50]]
		]
	]
	if subject [header-obj/subject: subj]
	either none? header-obj/from [
		if none? header-obj/from: from: system/user/email [net-error "Email header not set: no from address"]
		if all [string? system/user/name not empty? system/user/name][
			header-obj/from: rejoin [system/user/name " <" from ">"]
		]
	][
		from: header-obj/from
	]
	if none? header-obj/to [
		header-obj/to: tmp: make string! 20
		if show [
			foreach email address [repend tmp [email ", "]]
			clear back back tail tmp
		]
	]
	if none? header-obj/date [header-obj/date: to-idate now]

	if attach [
		boundary: rejoin ["--__REBOL--" system/product "--" system/version "--" checksum form now/precise "__"]
		header-obj/MIME-Version: "1.0"
		header-obj/content-type: join "multipart/mixed; boundary=" [{"} skip boundary 2 {"}]
		message: build-attach-body message files boundary
	]

	;-- Send as an SMTP batch or individually addressed:
	smtp-port: open [scheme: 'ssmtp]
	either only [ ; Only one message to multiple addrs
		address: copy address
		; remove non-email values
		remove-each value address [not email? :value]
		message: head insert insert tail net-utils/export header-obj newline message
		insert smtp-port reduce [ email	address message	]
	] [
		foreach addr address [
			if email? addr [
				if not show [insert clear header-obj/to addr]
				tmp: head insert insert tail net-utils/export header-obj newline message
				; probe tmp
				insert smtp-port reduce [from reduce [addr] tmp]
			]
		]
	]
	close smtp-port
]

resend: func [
	"Relay a message"
	to from message /local smtp-port
][
	smtp-port: open [scheme: 'ssmtp]
	insert smtp-port reduce [from reduce [to] message]
	close smtp-port
]

build-attach-body: function [
	{Return an email body with attached files.}
	body [string!] {The message body}
	files [block!] {List of files to send [%file1.r [%file2.r "data"]]}
	boundary [string!] {The boundary divider}
][
	make-mime-header
	break-lines
	file
	val
][
	make-mime-header: func [file] [
		net-utils/export context [
			Content-Type: join {application/octet-stream; name="} [file {"}]
			Content-Transfer-Encoding: "base64"
			Content-Disposition: join {attachment; filename="} [file {"^/}]
		]
	]
	break-lines: func [mesg data /at num] [
		num: any [num 72]
		while [not tail? data] [
			append mesg join copy/part data num #"^/"
			data: skip data num
		]
		mesg
	]
	if not empty? files [
		insert body reduce [boundary "^/Content-type: text/plain^/^/"]
		append body "^/^/"
		if not parse files [
			some [
				(file: none)
				[
					set file file! (val: read/binary file)
					| into [
						set file file!
						set val skip ;anything allowed
						to end
					]
				] (
					if file [
						repend body [
							boundary "^/"
							make-mime-header any [find/last/tail file #"/" file]
						]
						val: either any-string? val [val] [mold :val]
						break-lines body enbase val
					]
				)
			]
		] [net-error "Cannot parse file list."]
		append body join boundary "--^/"
	]
	body
]