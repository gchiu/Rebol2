rebol [
	Title: "test COMLib"
	File: %test-comlib.r
	Date: 26-Jun-2006
	Version: 1.0.1
	Progress: 0.5
	Status: "working"
	Needs: []
	Author: "Anton Rolls"
	Language: "English"
	Purpose: {Check that COMLib.r is working ok. Testing-ground for new features.}
	Usage: {}
	History: [
		1.0.0 [18-Dec-2005 {First version, tested on View 1.3.2} "Anton"]
		1.0.1 [26-Jun-2006 {working with comlib.r 1.1.3} "Anton"]
	]
	ToDo: {
	- 
	}
	Notes: {See also simple-start-comlib.r}
]

;query/clear system/words
COMLib: do %COMLib.r
;probe query/clear system/words


if error? set/any 'error try [ ; catch all errors so comlib/cleanup is always done
	
	COMLib/initialize
	;COMLib/initialize/only-these-routines/only-these-functions [][] 
	;COMLib/initialize/only-these-routines/only-these-functions []["CreateObject" "release"] ; <- check dependencies
	;COMLib/initialize/only-these-routines ["createObject"]
	;COMLib/initialize/only-these-functions ["CreateObject"]
	;COMLib/initialize/only-these-routines/only-these-functions ["createObject"]["getText"] 
	;COMLib/initialize/only-these-routines/only-these-functions ["getText"]["createObject"] ; test arguments reversed
	
	do bind [

		; <- use the COMLib API functions and routines here

		szHeadings: ["Mammals" "Birds" "Reptiles" "Fishes" "Plants"]

		xlApp: CreateObject "Excel.Application"

		;xlApp: createObject "Excel.ApplicationMISSPELLED"
		;release xlApp

		;PutValue [xlApp ".DisplayFullScreen = %b" "TRUE"] ; <- It actually wants a (BOOL)TRUE, but passing a string works too.
		PutValue [xlApp ".Visible = %b" "TRUE"]

		CallMethod [xlApp ".Workbooks.Add"]

		PutValue [xlApp ".ActiveSheet.Name = %s" "Critically Endangered"]

		{; test PutValue and GetString at high speed, alternating the value, to see if there are any latency problems.
		loop 5000 [
			PutValue [xlApp ".ActiveSheet.Name = %s" s1: "Hello"]
			s2: GetString [xlApp ".ActiveSheet.Name"]
			if s1 <> s2 [print ["s1 <> s2    s1:" s1 "s2:" s2] break]
			PutValue [xlApp ".ActiveSheet.Name = %s" s1: "Goodbye"]
			s2: GetString [xlApp ".ActiveSheet.Name"]
			if s1 <> s2 [print ["s1 <> s2    s1:" s1 "s2:" s2] break]
		]}

		repeat n 5 [
			PutValue compose [xlApp ".ActiveSheet.Cells(%d,%d) = %s" 1 n szHeadings/:n]
		]	
	
		; This causes real havoc with Excel, tries to fill every cell with the string, runs out of memory.
		;PutValue [xlApp ".ActiveSheet.Cells(1,10) = %s" "abc123"]

		; This sent my system to hell, used all my memory, which was not freed when I terminated EXCEL.EXE
		; The format string parameters must be specified separately, not inline as above.
		;GetString [xlApp ".ActiveSheet.Cells(1,10)"]

		; test memory stability of GetString (seems to be good)
		{large-string: copy "abc"  
		repeat n 5000 [append large-string form n]
		PutValue [xlApp ".ActiveSheet.Cells(%d,%d) = %s" 5 1 large-string]
		repeat n 1000 [
			string: GetString [xlApp ".ActiveSheet.Cells(%d,%d)" 5 1]
		]}

		release xlApp
		
	] COMLib/api

][
	;COMLib/routines/showLastException
	;wait 0.125
	;print ["COMLib Exception:^/" COMLib/routines/formatLastException]
	;wait 0.125
	print mold disarm error
]
;probe query/clear system/words

COMLib/cleanup
;probe query/clear system/words
