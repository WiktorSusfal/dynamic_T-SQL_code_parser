DESCRIPTION:
------------------------------------------
This solution was created to help with analyzing T-SQL code which consist of both: regular code and dynamic code 
(calculated as a string during SQL command execution and executed inside 'EXEC' or 'EXECUTE' function brackets.
The output of main procedure can be used for further analysis of SQL code - e.g. detection of database objects
used in dynamic SQL code.

To the main procedure there can be passed: 
- SQL code directly - via input parameter
- object database name, object schema name and object name which definition code has to be analyzed
- SQL job name, SQL job step name which definition code has to be analyzed. 

Then, the procedure will return a table where rows consist of information describing each particular line of code 
(or part of line of code) that was analyzed. When any column value describing the code changes, the line is splitted into
2 parts (the content before change and after) and stored in two separate rows. 

Algorithm can so far detect if particular part of SQL code is a part of:
 - plain string but not a part of dynamic SQL executed,
 - plain string inside dynamic SQL executed, 
 - dynamic SQL executed,
 - code inside EXEC or EXECUTE function brackets,
 - block comment in regular SQL code
 - block comment in dynamic SQL code executed
 - inline comment in regular SQL code
 - inline comment in dynamic SQL code executed
 - other regular SQL code 
 
The limitations are: 
- dynamic SQL code must be written as a plain string inside EXEC or EXECUTE function brackets; when there is an expression that combines
	plain strings and variables, the variables will be represented as '@'+variable name in the result table (not by value stored)
- EXEC functions with sp_executesql procedure and dynamic SQL code string given as a parameter cannot be used - they will be detected as a regular SQL code
- algorithm doesn't support '[]' and '""' operators - they are detected as a regular SQL code, so cannot contain any functional words (', /*, */, --, (, ), EXEC, EXECUTE)
	, otherwise the output will be incorrect 
- no support for nested EXECUTE statements - every argument of nested EXEC function treated as a plain string, so the "/*, (, ), */, --, '" are not functional there

Structure of the output table and examples of use are described in DESCRIPTION.txt file.
