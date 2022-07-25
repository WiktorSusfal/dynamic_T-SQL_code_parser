######################################################################################################################################################################
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
 
The strucuture of result table is as follows:
Column Name					Description 
-----------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- -TableKey				INT				- autoincremental key - counter for rows in output table
-- -LineNumber				INT 			- number of line in original code where the content stored in 'LineContent' column was found
-- -LineContent				NVARCHAR(MAX) 	- content of single line of original code (or part of single line) that can be described 
												by the values in following columns 
-- -IsPartOfRegularString	BIT 			- if '1' and IsDynamicSQLExecuted = '0' then the 'LineContent' is a part of 
												plain string written outside of the EXEC function brackets
-- -IsDynamicSQLExecuted	BIT 			- if '1' and IsPartOfRegularString = '0' then the 'LineContent' is a string 
												that represents code that is being executed inside EXEC functions of this procedure;
											- if '1' and IsPartOfRegularString = '1' then the 'LineContent' is a string 
												that represents plain string that is a part of dynamic SQL code
-- -InsideExecBrackets      BIT 			- if '1' then the 'LineContent' is inside EXEC brackets
-- -IsPartOfBlockComment	BIT 			- if '1' then the 'LineContent' is a part of block comment. 
												If IsPartOfRegularString = 0 and  IsDynamicSQLExecuted = 0 then the block comment is at the main level of code executed;
											- if IsDynamicSQLExecuted = 1 then 'LineContent' is a part of block comments 
												in dynamic SQL execudet inside code examined
-- -IsCommented				BIT 			- indicate if 'LineContent' is a part of in-line comment (--). 
												The dependencies on 'IsPartOfRegularString'	and 'IsDynamicSQLExecuted' are the same as above


The limitations are: 
- dynamic SQL code must be written as a plain string inside EXEC or EXECUTE function brackets; when there is an expression that combines
	plain strings and variables, the variables will be represented as '@'+variable name in the result table (not by value stored)
- EXEC functions with sp_executesql procedure and dynamic SQL code string given as a parameter cannot be used - they will be detected as a regular SQL code
- algorithm doesn't support '[]' and '""' operators - they are detected as a regular SQL code, so cannot contain any functional words (', /*, */, --, (, ), EXEC, EXECUTE)
	, otherwise the output will be incorrect 
- no support for nested EXECUTE statements - every argument of nested EXEC function treated as a plain string, so the "/*, (, ), */, --, '" are not functional there
######################################################################################################################################################################
######################################################################################################################################################################
EXAMPLES OF USE:
-------------------------------------------------

1. Lets give the code to be examined  for the procedure directly - via input parameter. 

The code:
SELECT 101 AS Column1, 102 AS Column2 -- SELECT 103 AS Column 3 

Output for the code in SSMS:
Column1		Column2
--------------------
101			102

Execution code of main procedure:
EXECUTE [dbo].[FR_SP_00_AnalyzeSQLCodeOfObjectDefinition] 
   @codeGivenByObjectName = 'N'
  ,@objectDefinition = N'SELECT 101 AS Column1, 102 AS Column2 -- SELECT 103 AS Column 3 '

Result table:
TableKey    LineNumber  LineContent                                     IsPartOfRegularString IsDynamicSQLExecuted InsideExecBrackets IsPartOfBlockComment IsCommented
----------- ----------- ----------------------------------------------- --------------------- -------------------- ------------------ -------------------- -----------
1           1           SELECT 101 AS Column1, 102 AS Column2           0                     0                    0                  0                    0
2           1           -- SELECT 103 AS Column 3                       0                     0                    0                  0                    1


#####################################################################################################################################################################
2. Lets give the code to be examined  for the procedure directly - via input parameter. 

The code:
SELECT 'some plain string' AS [Some_String]
EXECUTE ( 'SELECT 1 AS [Column_1] ' /* some commented content
end of some commented content*/ )

Output for the code in SSMS:

Some_String
-----------------
some plain string

Column_1
----------------
1

Execution code of main procedure:
EXECUTE [dbo].[FR_SP_00_AnalyzeSQLCodeOfObjectDefinition] 
   @codeGivenByObjectName = 'N'
  ,@objectDefinition = N'SELECT ''some plain string'' AS [Some_String]
EXECUTE ( ''SELECT 1 AS [Column_1] '' /* some commented content
end of some commented content*/ )'

Result table:
TableKey    LineNumber  LineContent                        IsPartOfRegularString IsDynamicSQLExecuted InsideExecBrackets IsPartOfBlockComment IsCommented
----------- ----------- ---------------------------------- --------------------- -------------------- ------------------ -------------------- -----------
1           1           SELECT                             0                     0                    0                  0                    0
2           1           'some plain string'                1                     0                    0                  0                    0
3           1            AS [Some_String]                  0                     0                    0                  0                    0
4           2           EXECUTE (                          0                     0                    0                  0                    0
5           2           'SELECT 1 AS [Column_1] '          0                     1                    1                  0                    0
6           2                                              0                     0                    1                  0                    0
7           2           /* some commented content          0                     0                    1                  1                    0
8           3           end of some commented content*/    0                     0                    1                  1                    0
9           3                                              0                     0                    1                  0                    0
10          3           )                                  0                     0                    0                  0                    0

#################################################################################################################################################################
3. Lets assume that there is SQL JOB named 'DynamicSQLAnalyzingTest' with step named 'Step_4' in the database.
Code of this step is: 

EXECUTE( --some inline comment
' INSERT INTO dbo.myTable VALUES (''SOME PLAIN STRING'') ' )

Execution code of main procedure:
EXECUTE [dbo].[FR_SP_00_AnalyzeSQLCodeOfObjectDefinition] 
   @codeGivenByObjectName = 'Y'
   ,@isSQLJob = 'Y'
   ,@objectName = 'DynamicSQLAnalyzingTest'
   ,@jobStepName = 'Step_4'
   
Result table:
 TableKey    LineNumber  LineContent                           IsPartOfRegularString IsDynamicSQLExecuted InsideExecBrackets IsPartOfBlockComment IsCommented
----------- ----------- ------------------------------------- --------------------- -------------------- ------------------ -------------------- -----------
1           1           EXECUTE(                              0                     0                    0                  0                    0
2           1                                                 0                     0                    1                  0                    0
3           1           --some inline comment                 0                     0                    1                  0                    1
4           2           ' INSERT INTO dbo.myTable VALUES (    0                     1                    1                  0                    0
5           2           ''SOME PLAIN STRING''                 1                     1                    1                  0                    0
6           2           ) '                                   0                     1                    1                  0                    0
7           2                                                 0                     0                    1                  0                    0
8           2           )                                     0                     0                    0                  0                    0

###################################################################################################################################################################
4. Lets assume that there is a SQL Stored procedure named 'dbo.TEST_SP' in the database named 'TEST_DB', created with code:

CREATE PROCEDURE [dbo].[TEST_SP] 
AS
BEGIN
/* ( '' ' abc ' ''  /* ) /**/*/ EXECUTE(N'Some statement that is not executed')
*/ EXEC /* not (' used code -- */ ( /* (-- ) */ -- xyz ( /*/* ) ' 
N' SELECT 1 -- ' + 'SELECT 2' + ' /*--*/ 
SELECT 3 ' -- some comment 
)
END


Output for the execution of procedure in SSMS:

(No column name)
--------------------
1

(No column name)
--------------------
3

Result table:
TableKey    LineNumber  LineContent                                                                        IsPartOfRegularString IsDynamicSQLExecuted InsideExecBrackets IsPartOfBlockComment IsCommented
----------- ----------- ---------------------------------------------------------------------------------- --------------------- -------------------- ------------------ -------------------- -----------
1           1           CREATE PROCEDURE [dbo].[TEST_SP]                                                   0                     0                    0                  0                    0
2           2           AS                                                                                 0                     0                    0                  0                    0
3           3           BEGIN                                                                              0                     0                    0                  0                    0
4           4           /* ( '' ' abc ' ''  /* ) /**/*/ EXECUTE(N'Some statement that is not executed')    0                     0                    0                  1                    0
5           5           */                                                                                 0                     0                    0                  1                    0
6           5            EXEC                                                                              0                     0                    0                  0                    0
7           5           /* not (' used code -- */                                                          0                     0                    0                  1                    0
8           5            (                                                                                 0                     0                    0                  0                    0
9           5                                                                                              0                     0                    1                  0                    0
10          5           /* (-- ) */                                                                        0                     0                    1                  1                    0
11          5                                                                                              0                     0                    1                  0                    0
12          5           -- xyz ( /*/* ) '                                                                  0                     0                    1                  0                    1
13          6           N' SELECT 1                                                                        0                     1                    1                  0                    0
14          6           -- '                                                                               0                     1                    1                  0                    1
15          6            +                                                                                 0                     0                    1                  0                    0
16          6           'SELECT 2'                                                                         0                     1                    1                  0                    1
17          6            +                                                                                 0                     0                    1                  0                    0
18          6           ' /*--*/                                                                           0                     1                    1                  0                    1
19          7           SELECT 3 '                                                                         0                     1                    1                  0                    0
20          7                                                                                              0                     0                    1                  0                    0
21          7           -- some comment                                                                    0                     0                    1                  0                    1
22          8           )                                                                                  0                     0                    0                  0                    0
23          9           END 																			   0                     0                    0                  0                    0
