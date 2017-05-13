#!/path/to/rebol -cs
REBOL [
    title: "Discordian dates"
    version: 0.0.2
    author: "Johan Forsberg"
    file: %discordian.r
    email: johan.forsberg.6117@student.uu.se
    date: 25-june-2001
    ddate: "Sweetmorn, Confusion 30, Year of Our Lady of Discord 3167"
    purpose: {Date Converter from the Gregorian to the Semi-Divinely
              Revealed POEE Calendar.}
    example: {poee-calendar/make-poee-date-string now}
    history: [
        0.0.1 [25-jun-2001 "First version" "Johan"]
        0.0.2 [25-jun-2001 "Corrected for ST. Tib's Day" "Johan"]
    notes: { altered by Graham Chiu so that acts as a SOAP service }
    ]
]

print {Content-type: text/xml; charset="utf-8"}

if system/options/cgi/request-method = "GET" [
	query-string: copy system/options/cgi/query-string
]

if system/options/cgi/request-method = "POST" [
	len_post: ( 20 + load system/options/cgi/content-length )
	post: make string! len_post
	while [0 < read-io system/ports/input post len_post ] []
	query-string: copy post
]

    seasons: ["Chaos" "Discord" "Confusion" "Bureaucracy" "The Aftermath"]
    
    weekdays: ["Setting Orange" "Sweetmorn" "Boomtime" "Pungenday" "Prickle"]
    
    holidays: [
        apostle ["Mungoday" "Mojoday" "Syaday" "Zaraday" "Maladay"]
        season ["Chaoflux" "Discoflux" "Confuflux" "Bureflux" "Afflux"]
    ]
    
    leap-year?: function [year] [] [
        return either ((year // 4) = 0) and ((year // 400) = 0) [true] [false]
    ] 

    get-day-of-year: function [date /notib] [day] [

        gregorian: [
            31 (either (not notib) and (leap-year? date/year) [29] [28]) 31 30 31 30
            31 31 30 31 30 31
        ]

        day: date/day
        for i 1 (date/month - 1) 1 [
            day: day + do gregorian/:i
        ]
        return day
    ]

    get-season-and-day: function [date] [day season] [
        day: get-day-of-year date
        season: 1
        ly: leap-year? date/year
        while [day > 73] [
            day: day - either (season = 1) and ly [
                74
            ] [
                73
            ]
            season: season + 1
        ]
        return reduce [
            either (season = 1) and (day > 59) [day: day - 1 (day = 59)] [false]
            season day
        ]
    ]
    
    make-poee-date: function [date] [] [
        sd: get-season-and-day date
        wd: ((get-day-of-year/notib date) // 5) + 1
        return compose [
            st-tibs-day (sd/1)
            weekday (pick weekdays wd)
            season (pick seasons sd/2)
            day (sd/3)
            year (date/year + 1166)
            holiday (
                switch/default sd/3 [
                    5 [pick holidays/apostle sd/2]
                    50 [pick holidays/season sd/2]
                ] [none]
            ) 
        ]
    ]

    make-poee-date-string: function [date] [pd] [
        pd: make-poee-date date
        return rejoin [
            either pd/st-tibs-day [
                "St. Tib's Day"
            ] [
                rejoin [pd/weekday ", " pd/season " " pd/day]
            ]
            ", Year of Our Lady of Discord " pd/year
            either none? pd/holiday [""] [rejoin [" -- " pd/holiday]]
        ]
    ] 

envelope: {<?xml version="1.0" encoding='UTF-8'?>
<SOAP-ENV:Envelope 
xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/" 
xmlns:xsd="http://www.w3.org/1999/XMLSchema" 
xmlns:xsi="http://www.w3.org/1999/XMLSchema-instance" 
xmlns:SOAP-ENC="http://schemas.xmlsoap.org/soap/encoding/">
<SOAP-ENV:Body><NS1:DiscordianResponse 
xmlns:NS1="http://tempuri.org/message/" 
SOAP-ENV:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
<NS1:return xsi:type="xsd:string">
</NS1:return>
</NS1:DiscordianResponse>
</SOAP-ENV:Body>
</SOAP-ENV:Envelope>}

errorMessage: {<soap:Envelope 
xmlns:soap='urn:schemas-xmlsoap-org:soap.v1'>
<soap:Body>
<soap:Fault>
<faultcode>200</faultcode>
<faultstring>
</faultstring>
<runcode>No</runcode>
</soap:Fault>
</soap:Body>
</soap:Envelope>}

sendResult: does [
	tmp: rejoin [ rday "/" rmonth "/" ryear ]
	if error? try [	tmp: make-poee-date-string to-date tmp ] [
		sendError join {Invalid Date of } tmp
		quit
	]
	insert find envelope {</NS1} tmp
	replace/all envelope newline " "
	content-length: rejoin [ "Content-Length: " length? envelope {^/} ]
	print content-length
	print envelope
]

sendError: func [ ermsg [string!]] [
	insert find errorMessage {</faultstring>} ermsg 
	replace/all errorMessage newline " "
	content-length: rejoin [ "Content-Length: " length? errorMessage {^/} ]
	print content-length
	print errorMessage
]

; query-string contains the stuff sent to the webserver
yearrule: [ thru "<year" thru ">" copy ryear to </year> ]
monthrule: [ thru "<month" thru ">" copy rmonth to </month> ]
dayrule: [ thru "<day" thru ">" copy rday to </day> ]

go: does [
	either all [	( parse query-string [ some yearrule to end ] ) 
		( parse query-string [ some monthrule to end ])
		( parse query-string [ some dayrule to end ] ) ]
	[ sendResult ]
	[ sendError {Incomplete SOAP message} ]
]

go
