rebol [
	Title: "Simple start COMLib"
	File: %simple-start-comlib.r
	Date: 29-Jun-2006
	Version: 1.0.0
	Progress: 0.99
	Status: "working"
	Needs: []
	Author: "Anton Rolls"
	Language: "English"
	Purpose: {The simplest, open/close COMLib script}
	Usage: {}
	History: [
		1.0.0 [29-Jun-2006 {First version} "Anton"]
	]
	ToDo: {
	-
	}
	Notes: {
		The error handling is recommended, but may not be necessary.

		See also test-comlib.r for a more complex, alternative way of using COMLib.
	}
]


if error? set/any 'error try [


	do/args %COMLib.r [

		; Use the COMLib API functions here.

	]


][
	print mold disarm error
]
