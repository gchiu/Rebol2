REBOL [
    Title: "async:// protocol (Asynchronous TCP)"
    Purpose: {
        This script installs a protocol handler that allows you to use
        async:// ports to simplify asynchronous I/O on TCP/IP ports.
        Please read the notes in the source code for more info.
    }
    Author: ["Gabriele Santilli" "Maarten Koopmans" "Romano Paolo Tenca"]
    EMail: giesse@rebol.it
    File: %async-protocol.r
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
    Date: 8-Feb-2005
    Version: 1.18.0 ; majorv.minorv.status
                    ; status: 0: unfinished; 1: testing; 2: stable
    History: [
        19-Aug-2003 1.1.0 "History start" Gabriele
        19-Aug-2003 1.2.0 "Fixed a bug in ON-RESOLVE (didn't close port)" Maarten
        19-Aug-2003 1.3.0 "Releasing under GPL" Gabriele
         5-Sep-2003 1.4.0 {
            Changed the async-modes handling (see: open on-connect insert on-data)
            on-data:
                - Changed the write handling: now the function returns after a single write,
                  else is blocking
                - local word 'done no more used
                - new local words (shortcut)
                - a stack problem arised in recursion, the check of the busy flag cannot stop the
                  recursion, so i changed insert, if this solution appears stable, the busy? flag
                  can be deleted (see more comment in the insert function code)
            insert:
                - changed async-modes and no more call to awake
            init:
                - load changed with to-tuple in init
                - port/locals now is initialized to an object with these words:
                    busy?  : as flag before
                    retry : counter for connection attempts, if > max-retry then access error
                    max-retry : max number of connect attempts (none! = forever)
                    max-transfer : max TCP transfer size accepted, moving this value to locals
                                   permit to set it for every port, it can also changed by the
                                   user in the awake 'write call
            on-connect:
                - now increases locals/retry, when > locals/max-retry then access error
                - new local words (shortcut)
            open:
                - (experimental) added a workaround for checking the existence of the awake
                  function: uses the new awake state 'open
                - use [port] eliminated: now sub-port is in dnsport/user-data
                - changed the name of local word sub-port to subport
            new routine handle-return for on-data
            'max-transfer moved to locals object
            'k word deleted         
        } Romano
         8-Sep-2003 1.5.0 {
            - in init [port/url: spec] deleted, what was for?
            - deleted awake test, now awake has a default function (see the end of the script)
            - support functions:
                * wait-find wait-start wait-stop, also for users
            - added support for open/write and open/read
            - if busy? now fire an error! (can we delete busy? beyond testing purposes?)
        } Romano
         8-Sep-2003 1.6.0 "Releasing" Gabriele
         9-Sep-2003 1.7.0 "Fixed bogus open/binary/with... (Thanks Romano)" Gabriele
        14-Feb-2004 1.8.0 "Re-releasing as BSD" Gabriele
        13-Apr-2004 1.9.0 "Added dns failure handling, changed close to support it" Romano
        13-Apr-2004 1.10.0 "Fixed a bug in dns failure handling" Gabriele
        27-Apr-2004 1.11.0 "Added asyncs:// (async SSL)" Gabriele
        28-Apr-2004 1.12.0 "Fixed asyncs:// (async SSL)" Gabriele
        25-May-2004 1.13.0 "Added attempt around sclose to avoid errors" Gabriele
        25-May-2004 1.14.0 "ATTEMPT around scopy dnsport too" Gabriele
        30/06/2004 1.15.0 "Fixed error in max-retry awake call" Romano
        13-Sep-2004 1.16.0 "Trying to workaround lack of dns:///async on Solaris" Gabriele
        16-Dec-2004 1.17.0 "Better handling of DNS ports" Gabriele
         8-Feb-2005 1.18.0 "Added some debug prints, replaced the on-data recursion error with a debug print" Gabriele
		10-Jun-2010 1.18.0 "Pushed to github"
    ]
]

;find, start and stop waiting, can be used also by users -Romano
wait-find: func [port [port!]][find system/ports/wait-list port]
wait-stop: func [port [port!]][remove wait-find port]
wait-start: func [port [port!]][insert tail system/ports/wait-list port]

if not value? 'debug [debug: func [cond val] [ ]]

async-protocol: make object! [
    {Note:
     The AWAKE function of an async:// port gets *TWO* arguments instead of one.
     The first is the port as usual; the second is the event that triggered the calling of
     AWAKE: it could be an ERROR!, indicating that something went wrong, or one of
     'connect (meaning connection established), 'read (meaning new data arrived), 'write
     (meaning all queued data was sent) or 'close (meaning peer closed connection).}
    
    ; based on Root-Protocol's init
    init: func [
        "Parse URL and/or check the port spec object"
        port "Unopened port spec"
        spec "Argument passed to open or make (a URL or port-spec)"
        /local scheme ip
    ] [
        if not port? port/sub-port [
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
                attempt [port/host: to-tuple port/host]
            ]
            if none? port/port-id [
                net-error reform ["No port address for" scheme "is specified"]
            ]
        ]
        ; we are pass-thru here.
        port/state/flags: port/state/flags or system/standard/port-flags/pass-thru
        ;made some values locals -Romano
        port/locals: make object! [
            busy?:          false   ; is true when we are inside on-data, used to avoid recursion
            max-retry:      25      ; max number of connection attempts (none! = forever) -Romano
            retry:          0       ; counter for retry -Romano
            max-transfer:   16 * 1024  ; max TCP transfer size accepted
            dnsport:        none    ; async dns port
        ]
    ]
    open: func [
        "Initiate the connection, AWAKE called when estabilished."
        port "Initalized port spec"
        /local subport tmp
    ] [
        net-utils/net-log reduce ["Opening async tcp connection"]
        either port? port/sub-port [
            ; turn an already opened TCP port into an async:// port
            port/sub-port/user-data: port ; parent port
            wait-start port/sub-port
            port/sub-port/async-modes: 'read
            port/sub-port/awake: :on-data
        ] [
            port/sub-port: subport: make port! compose [
                scheme: (select [async 'tcp asyncs 'ssl] port/scheme)
                host: port/host
                port-id: port/port-id
                timeout: port/timeout
                async-modes: 'connect
                awake: :on-connect
                user-data: port ; async parent port
            ]
            either tuple? subport/host [
                ; no need to resolve hostname, just try to connect
                wait-start subport
                ;call connect directly -Romano
                on-connect subport
            ] [
                ;use removed now subport in user-data -Romano
                ; DNS async not supported on Solaris. will be sync as workaround :(
                if error? try [
                    port/locals/dnsport: sopen/no-wait [
                        scheme: 'dns
                        host: "/async"
                        user-data: subport
                        awake: func [dnsport] [on-resolve dnsport dnsport/user-data]
                    ]
                    wait-start port/locals/dnsport
                    sinsert port/locals/dnsport subport/host
                ] [
                    wait-start subport
                    on-connect subport
                ]
            ]
        ]
        port/state/outBuffer: make string! 1024
        port/state/inBuffer: make string! 1024
    ]

    close: func [
        "Close the socket connection"
        port "An open port spec"
    ] [
        if port/locals/dnsport [
            wait-stop port/locals/dnsport
            attempt [sclose port/locals/dnsport]
        ]
        if port/sub-port [
        	wait-stop port/sub-port
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

    no-block:       -3      ; return code from IO indicating not to block
    would-block?:   func [err] [517 = get in err 'code] ; checks blocking error

    scopy: sopen: sinsert: sclose: spick: sset-modes: sget-modes: none
    foreach [w sw] [
        scopy copy              sopen open          sinsert insert
        sclose close            spick pick          sset-modes set-modes
        sget-modes get-modes
    ] [
        set w get in system/words sw
    ]

    on-resolve: func [dnsport port /local tmp] [
        ;debug true "on-resolve"
        either tmp: attempt [scopy dnsport] [
        	port/host: tmp
	        change wait-find dnsport port
	    	attempt [sclose dnsport]
            port/user-data/locals/dnsport: none
    	    port/awake port
    	    false
    	][
	    	wait-stop dnsport
	    	attempt [sclose dnsport]
            port/user-data/locals/dnsport: none
	    	port/user-data/sub-port: none
    		port/user-data/awake port/user-data make error! "Cannot resolve host name"
    	]
    ]
    on-connect: func [port /local err async modes] [
        ;debug true "on-connect"
        async: port/user-data
        either error? err: try [
            ; i'm not sure this is useful right now. -Gab
            ;modes: scopy [direct no-wait]
            ;if sget-modes async 'binary [append modes 'binary]
            ;sopen/mode/with port modes async/state/with
            sopen/direct/binary/no-wait port
        ] [
            if would-block? disarm err [
                if all [
                    ;check the number of retry -Romano
                    integer? async/locals/max-retry
                    async/locals/max-retry < async/locals/retry: async/locals/retry + 1
                ][
                    return async/awake async make error! reduce ['access 'no-connect port/host]
                ]
                return false
            ]
            wait-stop port
            return async/awake async :err
        ] [
            port/awake: :on-data
            async/awake async 'connect
            ; SSL does not like async-modes... the SSL handshake is not async!
            sset-modes port [async-modes: none]
            if port/scheme = 'ssl [sset-modes port [secure: true]]
            ; any data ready to send?
            sset-modes port either empty? async/state/outBuffer [
                [async-modes: 'read]
            ][
                [async-modes: [read write]]
            ]
        ]
        false
    ]

    ; handle the return from on-data on error -Romano
    handle-return: func [[throw] async [port!] value [any-type!] /local res][
        ;debug true "handle-return"
        set/any 'res async/awake async get/any 'value
        async/locals/busy?: false
        return get/any 'res
    ]

    ; now called only by event system -Romano
    on-data: func [port /local data err res async state max-transfer] [
        ;debug true "on-data"
        async: port/user-data
        ;useful? -Romano
        ; should no more be needed... -Gab
        ;if async/locals/busy? [
        ;    make error! "Internal error: recursive call to on-data: should not happen!"
        ;]
        debug async/locals/busy? "Recursive call to on-data!!! (Or, most likely, it was interrupted last time.)"
        state: async/state
        max-transfer: async/locals/max-transfer
        res: false
        async/locals/busy?: true
        ; try to receive
        data: make string! max-transfer + 2
        either error? err: try [read-io port data max-transfer] [
            if not would-block? disarm :err [
                handle-return async :err
            ]
        ] [
            if all [err < -1 err <> no-block] [
                handle-return async make error! join "read-io aborted (" [err ")"]
            ]
            if find/only [[0 tcp] [-1 tcp] [0 ssl]] reduce [err port/scheme] [
                ; port closed
                handle-return async 'close
            ]
            if err > 0 [
                sinsert tail state/inBuffer data
                res: res or async/awake async 'read
            ]
        ]
        ; try to send
        ;loop removed else sync -Romano
        if not empty? state/outBuffer [
            either error? err: try [
                write-io port state/outBuffer min max-transfer length? state/outBuffer
            ] [
                if not would-block? disarm :err [
                    handle-return async :err
                ]
            ] [
                if all [err < -1 err <> no-block] [
                    handle-return async make error! "write-io aborted"
                ]
                if err > 0 [
                    state/outBuffer: skip state/outBuffer err
                    if tail? state/outBuffer [
                        state/outBuffer: clear head state/outBuffer
                        res: res or async/awake async 'write
                        ;if no more data to write change the mode to 'read
                        if empty? state/outBuffer [port/async-modes: 'read]
                    ]
                ]
            ]
        ]
        async/locals/busy?: false
        res
    ]

    copy: func [port /part range /local res] [
        ;support for open/write -Romano
        if sget-modes port 'read [
            any [range range: tail port/state/inBuffer]
            res: scopy/part port/state/inBuffer range
            remove/part port/state/inBuffer range
        ]
        res
    ]

    insert: func [port data] [
        ;support for open/read -Romano
        if sget-modes port 'write [
            sinsert tail port/state/outBuffer data
            ; try to send, if port ready
            if port/sub-port/async-modes <> 'connect [
                port/sub-port/async-modes: [read write]
                ; The next statement was:
                ;port/sub-port/awake port/sub-port
                ; but the check of busy? in on-data can generate a caos in the function
                ; stack of on-data. I detected the bug in this situation:
                ; reading event
                ;   on-data busy?: true and call user awake
                ;       user awake call insert
                ;           insert call on-data
                ;               on-data checks busy? (true) and return false
                ;           insert return
                ;       user awake return
                ;   on-data >>> all on-data local vars are none!
                ;
                ; I think that it is not safe to do recursive call in an async event.
                ; If you know any better explanation, tell me, please.
                ; The workaround could be:
                ;
                ;if not port/locals/busy? [port/sub-port/awake port/sub-port]
                ;
                ; but i prefer to not call on-data from insert:
                ; 1) no recursive call to on-data
                ; 2) the value returned by user awake has no sense in insert
                ;if no recursive call can happen, we can delete the busy? word
                ;we must check
            ]
        ]
        port
    ]

    pick: func [port index] [
        ; maybe should return first char in inBuffer?
        none
    ]

    net-utils/net-install 'async self 0
    net-utils/net-install 'asyncs self 0
    ;the default awake routine -Romano
    system/schemes/async/awake: 
    system/schemes/asyncs/awake: func [port state [error! word!]][
        if error? :state [state]
        false
    ]
]
