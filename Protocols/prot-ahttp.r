REBOL [
    Title: "Asynchronous HTTP protocol for REBOL"
    Purpose: {
        A simple async://-based implementation of HTTP for REBOL.
    }
    Author: "Gabriele Santilli"
    EMail: giesse@rebol.it
    File: %prot-ahttp.r
    License: {
Copyright (c) 2003-2005, Gabriele Santilli
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions
are met:

* Redistributions of source code must retain the above copyright
  notice, this list of conditions and the following disclaimer. 
  
* Redistributions in binary form must reproduce the above
  copyright notice, this list of conditions and the following
  disclaimer in the documentation and/or other materials provided
  with the distribution. 

* The name of Gabriele Santilli may not be used to endorse or
  promote products derived from this software without specific
  prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
POSSIBILITY OF SUCH DAMAGE.
    }
    Date: 8-Feb-2004
    Version: 1.9.0 ; majorv.minorv.status
                   ; status: 0: unfinished; 1: testing; 2: stable
    History: [
        28-Apr-2004 1.1.0 "History start"
        29-Apr-2004 1.2.0 "First (maybe) working version"
        29-Apr-2004 1.3.0 "It wasn't"
        29-Apr-2004 1.4.0 "Fixed another bug"
         7-May-2004 1.5.0 "Fixed typo"
        20-May-2004 1.6.0 "Added timing so that it is possible to calculate download speed"
        20-May-2004 1.7.0 "Fixed a bug"
        25-May-2004 1.8.0 "Using attempt around sclose to avoid errors"
         8-Feb-2004 1.9.0 "Added a debug print"
    ]
]

context [
    {Note:
     The AWAKE function of an ahttp:// port gets *TWO* arguments instead of one.
     The first is the port as usual; the second is the event that triggered the calling of
     AWAKE: it could be an ERROR!, indicating that something went wrong, or 'close
     (meaning peer closed connection and all data is available in the port).}

    ; based on Root-Protocol's init
    init: func [
        "Parse URL and/or check the port spec object"
        port "Unopened port spec"
        spec "Argument passed to open or make (a URL or port-spec)"
        /local scheme ip
    ] [
        if url? spec [
            net-utils/url-parser/parse-url port spec
        ]
        scheme: port/scheme
        
        ;port/url: spec ; useless -Romano
        
        ; changed so that an IP address will be loaded into a tuple,
        ; to avoid having to load it each time to check if it is resolved or not
        ; I'm also using ATTEMPT to be safer -Gab
        either none? port/host [
            net-error reform ["No network server for" scheme "is specified"]
        ] [
            ;what load is for? -Romano
            ;if tuple? ip: attempt [load port/host] [port/host: ip]
            attempt [port/host: to tuple! port/host]
        ]
        if none? port/port-id [
            net-error reform ["No port address for" scheme "is specified"]
        ]
        ; we are pass-thru here.
        port/state/flags: port/state/flags or system/standard/port-flags/pass-thru
        port/locals: make object! [
            headers: none ; for compatibility with REBOL's http://
            data-ready?: no ; true when data is ready
            starttime: endtime: none ; used to calculate download speed
            bytes-read: 0 ; bytes read so far (including header)
        ]
    ]

    open: func [
        "Initiate the connection."
        port "Initalized port spec"

        /local http-header custom-headers target post-data
    ] [
        net-utils/net-log "Opening async HTTP connection"
        port/sub-port: sopen compose [
            scheme: (select [ahttp 'async ahttps 'asyncs] port/scheme)
            host: (port/host)
            port-id: (port/port-id)
            timeout: (port/timeout)
        ]
        port/sub-port/awake: :async-awake
        port/sub-port/user-data: port
        http-header: context [
            Accept: "*/*"
            Connection: "close"
            User-Agent: system/schemes/http/user-agent
            Host: port/host
        ]
        if all [block? port/state/custom custom-headers: select port/state/custom 'header block? custom-headers] [
            http-header: make http-header custom-headers
        ]
        all [port/user port/pass http-header: make http-header [Authorization: join "Basic " enbase join port/user [#":" port/pass]]]
        target: next mold to file! join "/" [any [port/path ""] any [port/target ""]]
        either all [block? port/state/custom post-data: find port/state/custom 'post any-string? post-data/2] [
            insert port/sub-port "POST "
            insert port/sub-port target
            insert port/sub-port " HTTP/1.0^M^J"
            http-header: make http-header [
                Content-Type: "application/x-www-form-urlencoded"
                Content-Length: length? post-data/2
            ]
            if block? post-data/3 [
                http-header: make http-header post-data/3
            ]
            insert port/sub-port replace/all net-utils/export http-header "^/" CRLF
            insert port/sub-port CRLF
            insert port/sub-port post-data/2
        ] [
            insert port/sub-port "GET "
            insert port/sub-port target
            insert port/sub-port " HTTP/1.0^M^J"
            insert port/sub-port replace/all net-utils/export http-header "^/" CRLF
            insert port/sub-port CRLF
        ]
    ]

    async-awake:
        func [port event [error! word!] /local http-port result-header pos start result-code result-string] [
            ;debug true "ahttp:// async awake"
            http-port: port/user-data
            if error? event [return http-port/awake http-port :event]
			; ?? event
            if event = 'connect [
                http-port/locals/starttime: now/precise
                return false
            ]
            if event = 'close [
                http-port/locals/endtime: now/precise
                http-port/state/inBuffer: scopy port
                http-port/locals/bytes-read: length? http-port/state/inBuffer
                result-header: context [
                    Date: Server: Last-Modified: Accept-Ranges: Content-Encoding: Content-Type:
                    Content-Length: Location: Expires: Referer: Connection: Authorization: none
                ]
                if not pos: find http-port/state/inBuffer "^M^J^M^J" [
                    return http-port/awake http-port make error! "Invalid HTTP header in response"
                ]
                parse/all http-port/state/inBuffer [
                    "HTTP/1." ["0" | "1"] " " copy result-code integer! " " copy result-string to "^M^J" "^M^J" start:
                ]
                if not all [string? result-code result-code: attempt [to integer! result-code] string? start] [
                    return http-port/awake http-port make error! "Invalid HTTP header in response"
                ]
                result-code: switch/default result-code [
                    200 ['ok]
                    201 ['ok]
                    204 ['ok]
                    300 ['forward]
                    301 ['forward]
                    302 ['forward]
                    304 ['ok]
                ] [
                    return http-port/awake http-port make error! join "Server reports error: " result-string
                ]
                result-header: parse-header result-header replace/all scopy/part start next next pos "^M^J" "^/"
                http-port/locals/headers: result-header
                if result-code = 'forward [
                    return http-port/awake http-port make error! "Redirects not (yet) supported"
                ]
                remove/part http-port/state/inBuffer skip pos 4
                http-port/locals/data-ready?: yes
                return http-port/awake http-port 'close
            ]
			if event = 'read [
				http-port/awake http-port 'read
			]
			if event = 'write [
				http-port/awake http-port 'write
			]
            false
        ]
        
    close: func [
        "Close the socket connection"
        port "An open port spec"
    ] [
        if port/sub-port [
            if all [port/locals/starttime not port/locals/endtime] [
                port/locals/endtime: now/precise
                port/locals/bytes-read: length? any [scopy port/sub-port ""]
            ]
	        attempt [sclose port/sub-port]
	    ]
    ]
    
    ; useless?
    get-sub-port: func [
        port "An open port spec"
    ] [
        port/sub-port
    ]

    ;Values returned by this function are never returned to user.
    ;It is the same for others schemes. Rebol Bug? -Romano
    get-modes: func [
        port "An open port spec"
        modes "A mode block"
    ] [
        sget-modes port/sub-port modes
    ]

    ;It is called only for NOT port-modes.
    ;Changes in port-modes do not call this routine. -Romano
    ; hmm, so this is what get-sub-port is for. but I think I need to intercept
    ; setting port-modes... I'll have to investigate. -Gab
    set-modes: func [
        port "An open port spec"
        modes "A mode block"
    ] [
        sset-modes port/sub-port modes
    ]

    scopy: sopen: sinsert: sclose: spick: sset-modes: sget-modes: none
    foreach [w sw] [
        scopy copy              sopen open          sinsert insert
        sclose close            spick pick          sset-modes set-modes
        sget-modes get-modes
    ] [
        set w get in system/words sw
    ]

    copy: func [port /part range /local res] [
        if port/locals/data-ready? [
            any [range range: tail port/state/inBuffer]
            res: scopy/part port/state/inBuffer range
            remove/part port/state/inBuffer range
        ]
        res
    ]

    ;insert: none

    ;pick: none

    net-utils/net-install 'ahttp self 80
    net-utils/net-install 'ahttps self 443
    ;the default awake routine -Romano
    system/schemes/ahttp/awake:
    system/schemes/ahttps/awake: func [port state [error! word!]][
        if error? :state [state]
        false
    ]
]
