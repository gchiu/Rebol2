rebol [
	Title: "COMLib (the rebol side of the com2rebol interface)"
	File: %COMLib.r
	Date: 9-Mar-2007
	Version: 1.1.9
	Progress: 0.55
	Status: "working, everything reengineered"
	Needs: []
	Author: "Anton Rolls"
	Original-Author: "Benjamin Maggi"
	Language: 'English
	Purpose: {Create the rebol side of the com2rebol interface}
	License: {COMLIB is open source software provided under the BSD license.}
	library: [
		level:    'advanced
		platform: 'windows
		type:     []
		domain:   [external-library win-api]
		tested-under: [view/pro 1.3.2.3.1 on WXP]
		support:  none
		license:  'BSD
		see-also: none
	]
	Usage: {
		do/args %COMLib.r [
			; use the comlib api functions and routines here
		]

	Or

		COMLib: do %COMLib.r
		COMLib/initialize
		do bind [
			; use the comlib api functions and routines here
		] COMLib/api
		COMLib/cleanup
	}
	History: [
		1.0.0 [3-Dec-2005 {First version forked from Benjamin Maggi's COMLib.r,
			making official rebol style compliant; 
			args were incorrectly "declared" local in the function body, added them as locals to the function
			spec block correctly;
			renamed "exaptionThrown" -> "exceptionThrown?" ;
			renamed "dipsHelper" -> "dispHelper" (needed to recompile DLL)
			switch to-string type? -> switch type?/word ;
			removed all the unnecessary COMPOSE/DEEPs when making routines;
		} "Anton"]
		1.0.1 [4-Dec-2005 {Major rework of genericGetVal, made it more rebolish, removed first argument
			(which wasn't used)
		} "Anton"]
		1.0.2 [17-Dec-2005 {wrapped in context in a format similar to the output of my 
			make-external-library-interface.r} "Anton"]
		1.0.3 [18-Dec-2005 {changing the format to be quite different} "Anton"]
		1.0.4 [20-Dec-2005 {finished implementing the dependency handling code, finished converting
			routines to "storage" format} "Anton"]
		1.0.5 [21-Dec-2005 {optimized genericGetVal more, removed some unnecessary variables,
			no longer setting a word to the created routine; renamed lib -> library} "Anton"]
		1.0.6 [5-Jun-2006 {routine spec for toggleExceptions was empty (no args) so added the int arg,
			spec of api functions is now correctly bound to api, fixed bug in genericGetVal where the type?/word
			return-type was used instead of to-word return-type} "Anton"]
		1.0.7 [6-Jun-2006 {initialize now does initDispHelper and cleanup now does closeDispHelper, so both
			of these are always added to routines} "Anton"]
		1.0.8 [10-Jun-2006 {removed makeContainer, was not properly functioning and was not used anywhere,
			implemented more of setErrorHandler, renamed setErrorHandler -> setExceptionHandler} "Anton"]
		1.0.9 [16-Jun-2006 {reworked substantially for new exception handling, split api context into two contexts,
			api and routines} "Anton"]
		1.1.0 [17-Jun-2006 {renamed SendValue -> PutValue, removed any-type! for optional arguments, since it will
			cause accidental user code errors, switched order of first two arguments in GenericGetVal, renamed
			retrieveObject -> GetObject, renamed objectMethod -> CallMethod and reworked argument handling} "Anton"]
		1.1.1 [18-Jun-2006 {renamed genericGetVal -> do-variadic-routine, and now it checks the arg types} "Anton"]
		1.1.2 [20-Jun-2006 {renamed getNumber -> getInteger, renamed getText -> getString, removed installObject} "Anton"]
		1.1.3 [25-Jun-2006 {added EnumNextObject, added FOR_EACH (untested)} "Anton"]
		1.1.4 [29-Jun-2006 {added optional method of using comlib via do/args -> system/script/args
			throwing real errors in initialize instead of just printing error messages, initialize catches error
			during load-library and throws} "Anton"]
		1.1.5 [2-Jul-2006 {debugging and completing FOR_EACH, EnumBegin and EnumNextObject} "Anton"]
		1.1.6 [7-Jul-2006 {added putRef and PutRef} "Anton"]
		1.1.7 [10-Jul-2006 {added missing [catch] to GetObject, PutValue and PutRef} "Anton"]
		1.1.8 [11-Jul-2006 {cleanup now releases any forgotten unreleased objects that were created by
			CreateObject or GetObject} "Anton"]
		1.1.9 [9-Mar-2007 {backwards compatibility fixes (only tested on %test-comlib.r):
			reset series to head after FORALL (necessary in older rebol versions),
			defining CASE mezzanine function for older rebols (eg. view < 1.2.54),
			workaround bug in View < 1.2.54 on converting datatype to word (eg. to-word integer!) using MOLD
		} "Anton"]
	]
	ToDo: {
	- When user doesn't have External Library Access, the error is not very clear.
	  Also the error caused by a missing com2rebol.dll file is not clear.
	- release should avoid passing NONE to releaseObject somehow, so can support code like:
		obj: attempt [CreateObject [...]]
		release obj
	- release should accept integer arg directly (not just literal word) too ?
	  (That would allow large lists of anonymous objects stored as a block of integers for instance.)

	- argument syntax errors were causing EXCEL.EXE to hang around (probably because objects were not released).
	  This is probably now fixed by cleanup releasing forgotten objects.

	- I am not clear about this, but speech.r was not trapping an exception in putValue until after 
	  I added toggleExceptions 1
	  Now it seems to be trapping it without using toggleExceptions... is the COM system remembering ?
	  (Try again after a restart.)
	  (could be extra confusion with the missing [catch] in PutValue ?)

	- free-library should not error when the library is already freed

	- implement WITH macro ? (see excel.r, just using GetObject and release)

	- name IDispatch * arguments consistently, currently we have "obj" (most popular), "object", "parent" and "ppDisp"

	- all arguments should be passed in a block to be consistent ? These ones are not:
	  - failed?
	  - CreateObject
	  - release

	- fix up the rebol.org library script header, type and license

	- GetString appears to be fine, now also test  GetValue %s  millions of times, watching mem use.

	- perhaps guard against these buggy problems:

		; This causes real havoc with Excel, tries to fill every cell with the string, runs out of memory.
		;PutValue [xlApp ".ActiveSheet.Cells(1,10) = %s" "abc123"]

		; This sent my system to hell, used all my memory, which was not freed when I terminated EXCEL.EXE
		; The format string parameters must be specified separately, not inline as above, and like this:
		;GetString [xlApp ".ActiveSheet.Cells(1,10)"]
	
	- decide how to handle pointers, as integer! or as binary!

	- maybe make some ansi<->Unicode functions, so we can support unicode in rebol ?
	  - check Ben's existing implementations

	- write the original types for each of the routine arguments (in the storage)
	- remove toggleExceptions ? It won't be used very often, only if the rebol exception handling fails for some reason.
	- see Ben's TODO list in his comlib.r
	- maybe make some functions sizeof_LPCWSTR, sizeof_WCHAR etc. so we can judge the size of memory to allocate accurately?
	  (I wanted this for creating an exception struct, which now seems not necessary.)
	}
	Notes: {
	- exporting from Microsoft Outlook
	  http://www.microsoft.com/technet/scriptcenter/resources/officetips/may05/tips0517.mspx

	- This is how initialize works:

		stored-routines: [...]
		stored-api-funcs: [...]

		stored-routines (all routine specs)
				|
			/only-these-routines routine-names             <-- maybe rename back to /selected-routines
					|
				   my-routines

		stored-api-funcs (all api function specs)
				|
			/only-these-functions function-names           <-- maybe rename back to /selected-functions
					|
				   my-functions

		Check dependencies of stored-api-funcs and extend the selected (routine or api) specs as necessary

		routines: context my-routines
		api: context my-functions

	- Dependency information is in stored-routines and stored-api-funcs, eg, the release function needs the releaseObject routine: 
		
		"release" [
			func [
				'object
			][
				releaseObject get object
				set object none
			]
		]["releaseObject"]   ; <-- list of dependencies

	- API and ROUTINES are separate contexts.
	  ROUTINES contains routines which interface to the DLL functions.
	  API contains rebol functions which comprise the Application Programmer Interface.
	  Many of the API functions wrap a routine with the same name, except the first letter is lowercase.
	  In the DLL the wrapped functions also lowercase the first letter.

		So the functions are named like so:

		        comlib.r                       com2rebol.c          disphelper.c

		   API
		 function!       routine!                function             function

		CreateObject -> createObject    ->    createObject   ->    dhCreateObject
		PutValue     -> putValue        ->    putValue       ->    dhPutValueV
		CallMethod	 -> callMethod      ->    callMethod     ->    dhCallMethod		  
	}
]

context [

    library-file: clean-path %com2rebol.dll
    library: none
    load-library: func ["Load the external library."][library: load/library library-file] 
    free-library: func ["Free the external library."][free library library: none] 

	cleanup: func ["Release any unreleased objects and Free the COMLib DLL"
	][
		; release objects that the user has made using createObject and GetObject
		foreach obj objects [routines/releaseObject obj]
		clear objects

		free-library

		; <- also try to free memory by unsetting words etc.
	]

	objects: none

	api: none
	routines: none

	error: none
	;exception: none ; struct! to store a DispHelper exception  (DH_EXCEPTION, * PDH_EXCEPTION)

	; define CASE mezzanine function if not present (backwards compatibility)
	case: either value? in system/words 'case [
		get in system/words 'case ; use the native function built-in since View 1.2.54
	][
		case: func [  
			"Find a condition and evaluates what follows it."  
			[throw]  
			cases [block!] "Block of cases to evaluate."  
			/default  
			case "Default case if no others are found."  
			/local condition body  
		][  
			while [not empty? cases][  
				set [condition cases] do/next cases  
				if condition [  
					body: first cases  
					break  
				]  
				cases: next cases  
			]  
			do any [
				body
				case
			]  
		]
	]

	initialize: func ["Loads the COMLib DLL (external library) and creates the API ready for use. (Returns the api object.)"
		[catch]
		/only-these-routines routine-names {Make only a limited set of the routines named in routine-names (to save memory). eg. ["createObject"]} 
		/only-these-functions function-names {Make only a limited set of the api functions (or values) named in function-names}
		/local my-routines my-functions all-routine-names all-function-names unknowns make-array
	][
		if error? set/any 'error try [load-library][throw error]

		my-routines: all-routine-names: extract stored-routines 3 ; default to all routines
		if only-these-routines [
			if not empty? unknowns: exclude routine-names my-routines [
				throw make error! reform ["Selected routines not available:" mold unknowns]
			]
			my-routines: intersect my-routines routine-names
		]
		if not find my-routines "releaseObject" [append my-routines "releaseObject"] ; <- needed by cleanup
		;?? my-routines

		my-functions: all-function-names: extract stored-api-funcs 3 ; default to all api functions
		if only-these-functions [
			if not empty? unknowns: exclude function-names my-functions [
				throw make error! reform ["Selected api functions not found:" mold unknowns]
			]
			my-functions: intersect my-functions function-names
		]
		;?? my-functions

		foreach [name spec routine] stored-routines [ ; step through all the routines
			; check types of name, spec, routine
			if not all [string? name block? spec string? routine][
				throw make error! reform ["COMLib syntax error: storage format spec incorrect for routine:" mold name]
			]
		]

		; Check dependencies and extend routines or the api as necessary. (extend my-routines and my-functions)

		foreach [name spec dependencies] stored-api-funcs [ ; step through all the functions
			; check types of name spec dependencies
			if not all [string? name block? spec any [dependencies = 'none block? dependencies]][
				throw make error! reform ["COMLib syntax error: storage format spec incorrect for:" mold name]
			]
			; (careful, dependencies can be the word 'none)
			if all [find my-functions name block? dependencies][ ; is it one of the functions to go into the api, and does it have dependencies ?
				foreach dependency dependencies [
					case [
						find all-routine-names dependency [if not find my-routines dependency [append my-routines dependency]]
						find all-function-names dependency [if not find my-functions dependency [append my-functions dependency]]
						"default" [
							throw make error! reform ["COMLib: The function" name "depends on" dependency "but" dependency "is not available."]
						]
					]
				]
			]
		]

		;?? my-routines
		;?? my-functions

		; create the routines context
		; populate a context spec block with set-words from my-routines 
		routines: copy [none]   foreach word my-routines [insert back tail routines to-set-word word]
		routines: context routines

		; create the api context 
		; populate a context spec block with set-words from my-functions
		api: copy [none]   foreach word my-functions [insert back tail api to-set-word word]
		api: context api

		; make routines and functions and set them into the words in the context
		foreach [name spec mangled] stored-routines [
			if find my-routines name [
				make-routine name spec mangled
			]
		]
		foreach [name spec dependencies] stored-api-funcs [
			if find my-functions name [
				set in api to-word name do bind bind spec api routines
				; BINDed last to routines context so routines with the same name as api functions take precedence.
				; This is because most api functions wrap a routine with the same name (with only case of first letter different).
			]
		]

		
		make-array: func [length [integer!] spec [block!] "eg: [ch [char!]]" /local result][
			result: copy []
			repeat n length [foreach [name type] spec [repend result [to-word join name n type]]]
			result
		]

		{; struct! to store a DispHelper exception  (DH_EXCEPTION, * PDH_EXCEPTION)
		exception: make struct! compose/deep [
			[save]
			InitialFunction [string!] ; LPCWSTR szInitialFunction;
			ErrorFunction [string!] ; LPCWSTR szErrorFunction;

			hr [int] ; HRESULT hr;

			(make-array 64 [m0_ [char] m1_ [char]]) ; WCHAR szMember[64] (WCHAR is unsigned short, typedef'd in winnt.h)
			(make-array 256 [c0_ [char] c1_ [char]]) ; WCHAR szCompleteMember[256]

			Code [int] ; UINT swCode;
			Description [string!] ; LPWSTR szDescription;
			Source [string!] ; LPWSTR szSource;
			HelpFile [string!] ; LPWSTR szHelpFile;
			HelpContext [int] ; DWORD dwHelpContext (unsigned long, typedef'd in windef.h)

			ArgError [int] ; UINT iArgError;

			DispatchError [int] ; BOOL bDispatchError;

			;#ifdef DISPHELPER_INTERNAL_BUILD
			Old [int] ; BOOL bOld;
			;#endif
		] none

		;print ["sizeof exception:" length? third exception] ; == 684 (correct)

		;api/setException third exception ; <- 
		}

		objects: copy []

		api
	]
	
    make-routine: func [
        name [string!] 
        spec [block!] 
        mangled [string!]
    ] [
        if error? set/any 'error try [
            set in routines to-word rebolify name make routine! rebolify-spec spec library mangled
        ] [
            make error! reform ["COMLib: Problem creating routine for symbol:" mold name mold disarm error]
        ]
    ]

	rebolify: func [{create the more rebolish version of the c symbol name} 
        name [string!] "c symbol name"
    ][
        name
    ]
    rebolify-spec: func [{convert block of c-style arguments closer to rebol routine! spec style} 
        spec [block!]
    ][
        spec: copy spec 
		;?? spec
        forskip spec 3 [
            either spec/1 = 'return [spec/1: to-set-word 'return] [spec/1: to-word rebolify spec/1]
        ] 
        head spec
    ]

	check-types: func [
		[catch]
		name [string!] args [block!] types [block!] 
	][
		repeat n length? types [
			if types/:n <> type?/word args/:n [
				throw make error! compose [script expect-arg (name) (join "args/" n) (types/:n)]
			]
		]
	]

	; generate a routine on the fly, to handle variadic functions (functions with a variable number of arguments)
	do-variadic-routine: func [
		[catch]
		return-type [datatype!] ; eg. integer!  or  string!
		dll-func-name [string!] ; eg. "getInteger", "getString", "getObj" "putValue" or "enumBegin"
		args [block!] ; [integer! string!] "types other than integer or string are passed as integer"
		types [block!] ; block of types that args must contain
		/local err routine-spec count routine
	][
		args: reduce args
		
		; convert logic!s to integer!
		forall args [if logic? args/1 [args/1: to-integer args/1]] ; <-- most likely BOOL represented as int
		args: head args ; backwards compatibility for FORALL, which used to leave series at tail

		throw-on-error [check-types dll-func-name args types]

		routine-spec: copy []

		count: 0
		foreach arg args [
			append routine-spec compose/only [
				(to-word join "arg_" count) (
					case [
						string? arg [[string!]] 
						binary? arg [[binary!]]
						arg [[integer!]] ; integer or any other type is passed as integer
					]
				)
			]
			count: count + 1
		]

		append routine-spec compose/deep [
			return: [(to-word mold return-type)] ; <-- MOLD only used for backwards compatibility for View < 1.2.54
		]

		routine: make routine! routine-spec library dll-func-name
		do compose [routine (args)] ; call the routine with the specified args and return the result
	]

	stored-routines: [
		"showMessage" [
			"message"	[string!] "LPCSTR"
		] "showMessage"

		"toggleExceptions" [
			"option"	[integer!] "int"
		] "toggleExceptions"
			
		;"setException" [
		;	"exception" [binary!] "PDH_EXCEPTION exception"
		;	; return void
		;] "setException"

		"formatLastException" [
			return: [string!] "LPCSTR"
		] "formatLastException" 

		"showLastException" [] "showLastException"


		"createObject" [
			"objName"	[string!] "LPCSTR ansiObjName"
			"ppDisp"    [binary!] "IDispatch **ppDisp"
			return		[integer!] "HRESULT"
		] "createObject"	

		"releaseObject" [
			"obj"		[integer!] ""
			return		[integer!] "HRESULT"
		] "releaseObject"


		"getObject" [
			"result"	[binary!] "IDispatch **"
			"parent"	[integer!] ""
			"szMember"	[string!] ""
			return		[integer!] ""
		] "getObject"

		; These just test that the routines can be made from the variadic functions. They will actually be made on the fly later.

		"callMethod" [
			"obj"		[integer!] "IDispatch *"
			"szMember"	[string!] "LPCSTR"
			"test"		[string!] ""
			return		[integer!] "HRESULT"
		] "callMethod"

		"putValue" [
			"obj"		[integer!] "IDispatch *"
			"szMember"	[string!] ""
			"test"		[string!] ""
			return		[integer!] ""
		] "putValue"

		;"putValueInteger" [
		;	"obj"		[integer!] ""
		;	"szMember"	[string!] ""
		;	"test"		[integer!] ""
		;	return		[integer!] ""
		;] "putValue"

		"getInteger" [
			"result"	[binary!] "UINT *"
			"object"	[integer!] ""
			"szMember"	[string!] ""
			return		[integer!] "HRESULT"
		] "getInteger"

		"getString" [
			"result"	[binary!] "LPCSTR *"
			"object"	[integer!] ""
			"szMember"	[string!] ""
			return		[integer!] "HRESULT"
		] "getString"

		"getStringCleanup" [] "getStringCleanup"  ; <- this frees the string created by getString in the DLL memory

		"putRef" [
			"obj" 		[integer!] "IDispatch *"
			"szMember" 	[string!] "LPCSTR"
			return		[integer!] "HRESULT"
		] "putRef"

		;enumBegin(IEnumVARIANT **ppEnum, IDispatch *pDisp, LPCSTR szMember, ...);
		"enumBegin" [
			"ppEnum"	[binary!] "IEnumVARIANT **"
			"obj"		[integer!] "IDispatch *"
			"szMember"	[string!] "LPCSTR"
			return		[integer!] "HRESULT"
		] "enumBegin"

		;enumNextObject(IDispatch **ppDisp, IEnumVARIANT *pEnum);
		"enumNextObject" [
			"ppDisp"	[binary!] "IDispatch **"
			"enum"		[integer!] "IEnumVARIANT *"
			return		[integer!] "HRESULT"
		] "enumNextObject"
	]

	stored-api-funcs: [ ; storage format for the context spec

		"failed?" [
			func [
				hr [integer!] "HRESULT"
			][
				hr < 0  ; winerror.h :  #define FAILED(Status) ((HRESULT)(Status)<0)
			]
		] none

		"FormatLastException" [
			func [][replace/all formatLastException crlf lf]
		] none

		; these functions wrap the equivalent routines so can handle exceptions and throw them as rebol errors

		"CreateObject" [
			func [
				[catch]
				objName [string!]
				/local hr str
			][
				ppDisp: make struct! [int [int]][0] ; IDispatch *
				
				hr: createObject objName third ppDisp

				if failed? hr [
					;print ["createObject caused an exception, hr:" hr to-hex hr]
					;print ["Exception:^/" api/formatLastException]
					throw make error! api/FormatLastException
				]
				insert objects ppDisp/int ; remember this object so we can release automatically on cleanup
				ppDisp/int
			]
		] none

		"release" [
			func [
				'object
			][
				;print ["release" mold object]

				;if not none? get object [
				releaseObject get object
				if find objects get object [remove find objects get object]
				;]

				;set object none ; <---
				set object 0
			]
		] ["releaseObject"]

		"CallMethod" [
			func [
				[catch]
				args [block!] "[obj [integer!] szMember [string!] ...] Any extra args should be string! or integer!"
				/local hr
			][
				throw-on-error [ ; rethrow type-check errors thrown by do-variadic-routine
					hr: do-variadic-routine integer! "callMethod" args [integer! string!]
				]
				if failed? hr [throw make error! api/FormatLastException]
				hr
			]	
		] ["failed?" "callMethod"]

		"GetObject" [
			func [
				[catch]
				args [block!] "[obj [integer!] szMember [string!] ...]"
				/local hr result
			][
				result: make struct! [int [int]] none
				insert args: copy args third result
				throw-on-error [
					hr: do-variadic-routine integer! "getObject" args [binary! integer! string!]
				]
				if failed? hr [throw make error! api/FormatLastException]
				insert objects result/int ; remember this object so we can release automatically on cleanup
				result/int
			]
		] ["getObject"]

		"PutValue" [
			func [
				[catch]
				args [block!] "[obj [integer!] szMember [string!] ...]"
				/local hr
			][
				throw-on-error [
					hr: do-variadic-routine integer! "putValue" args [integer! string!]
				]
				;print ["PutValue hr:" hr]
				if failed? hr [throw make error! api/FormatLastException]
				hr
			]
		] ["putValue"]

		"PutRef" [
			func [
				[catch]
				args [block!] "[obj [integer!] szMember [string!] ...]"
				/local hr
			][
				throw-on-error [
					hr: do-variadic-routine integer! "putRef" args [integer! string!]
				]
				if failed? hr [throw make error! api/FormatLastException]
				hr
			]
		] ["putRef"]

		
		"GetInteger" [
			func [
				[catch]
				args [block!] "[obj [integer!] szMember [string!] ...]"
				/local hr result
			][
				result: make struct! [int [int]] none
				insert args: copy args third result
				throw-on-error [
					hr: do-variadic-routine integer! "getInteger" args [binary! integer! string!]
				]
				if failed? hr [throw make error! api/FormatLastException]
				result/int
			]
		] ["getInteger"]

		"GetString" [
			func [
				[catch]
				args [block!] "[obj [integer!] szMember [string!] ...]"
				/local hr result
			][
				result: make struct! [string [string!]] none
				insert args: copy args third result
				throw-on-error [
					hr: do-variadic-routine integer! "getString" args [binary! integer! string!]
				]
				if failed? hr [throw make error! api/FormatLastException]
				getStringCleanup ; let the DLL know we are finished with its string
				result/string
			]
		] ["getString"]

		"EnumBegin" [
			func [
				[catch]
				args [block!] "[obj [integer!] szMember [string!] ...]" ; IDispatch *pDisp, LPCSTR szMember, ...
				/local hr result
			][
				result: make struct! [int [int]] none ; IEnumVARIANT **ppEnum
				insert args: copy args third result
				throw-on-error [
					hr: do-variadic-routine integer! "enumBegin" args [binary! integer! string!]
				]
				if failed? hr [throw make error! api/FormatLastException]
				result/int
			]
		] ["enumBegin"]

		"EnumNextObject" [
			func [
				[catch]
				args [block!] "[enum [integer!]]" ; IEnumVARIANT *pEnum
				/local hr result
			][
				;print "EnumNextObject"
				result: make struct! [int [int]] none ; IDispatch **ppDisp
				insert args: copy args third result
				throw-on-error [
					hr: do-variadic-routine integer! "enumNextObject" args [binary! integer!]
				]
				if failed? hr [throw make error! api/FormatLastException]
				result/int
			]
		]["enumNextObject"]

		;#define FOR_EACH0(objName, pDisp, szMember) { \
		;	IEnumVARIANT * xx_pEnum_xx = NULL;    \
		;	DISPATCH_OBJ(objName);                \
		;	if (SUCCEEDED(dhEnumBegin(&xx_pEnum_xx, pDisp, szMember))) { \
		;		while (dhEnumNextObject(xx_pEnum_xx, &objName) == NOERROR) {

		;#define FOR_EACH1(objName, pDisp, szMember, arg1) { \
		;	IEnumVARIANT * xx_pEnum_xx = NULL;          \
		;	DISPATCH_OBJ(objName);                      \
		;	if (SUCCEEDED(dhEnumBegin(&xx_pEnum_xx, pDisp, szMember, arg1))) { \
		;		while (dhEnumNextObject(xx_pEnum_xx, &objName) == NOERROR) {

		;#define NEXT(objName) SAFE_RELEASE(objName); }} SAFE_RELEASE(objName); SAFE_RELEASE(xx_pEnum_xx); }

		"FOR_EACH" [
			func [
				[catch]
				;args [block!] "[objName [string!] obj [integer!] szMember [string!] ...]"
				args [block!] "[word [word!] obj [integer!] szMember [string!] ...]"
				code-body [block!]
				/local word ctx enum
			][
				; <- check types
				word: args/1

				ctx: context compose [(to-set-word word) none]

				enum: api/EnumBegin (copy next args) ; IEnumVARIANT **  ; <- trap error here too

				while compose/deep [

					throw-on-error [
						(to-set-word in ctx word) api/EnumNextObject [enum]
					]
					;?? (in ctx word)
	
					0 <> (in ctx word)
				] bind code-body ctx

				do compose [release (in ctx word)]
				release enum
			]
		] none ; [api/EnumBegin api/EnumNextObject]  <-- should be this

	]

	; If the user script passed a code block with DO/ARGS, then we
	; initialize, bind and do the user code, and finally cleanup.

	if block? system/script/args [ ; <- user script passed a code block

		set/any 'error try [ ; catch all errors so cleanup is always done
	
			initialize
			do bind system/script/args api ; <- use the COMLib API functions
		]
		cleanup
		get/any 'error ; let the last result return, or fire the error so the user can handle it
	]
]