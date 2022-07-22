-- =============================================
-- Author:		Wiktor Susfał
-- Create date: <Create Date,,>
-- Description:	Table function to parse given source code to table (line by line). Each record assigned to particular line of code contains info of:
				-- -TableKey - autoincremental int key
				-- -LineNumber - number of line in code (if line contains comment (started with "--") then the line is splitted to two records in result table:
			    --             - record with uncommented content
				--             - record with commented content
				-- -LineContent
				-- -DatabaseScope - which database is currently used
				-- -IsPartOfString - is it part of string surrounded by ''
				-- -IsPartOfBlockComment - is it part of comment surrounded by /**/
				-- -IsCommented  - is it part of line of code beghind the '--'
-- =============================================
CREATE FUNCTION [dbo].[FR_TVF_00_ParseDefinitionCode]
(
	@definitionCode NVARCHAR(MAX) = N''
)
RETURNS 
@informationTable TABLE 
(
	TableKey				INT PRIMARY KEY IDENTITY(1, 1)
	,LineNumber				INT NOT NULL
	,LineContent			NVARCHAR(MAX)
	,IsPartOfString			BIT NOT NULL
	,IsDynamicSQLExecuted	BIT NOT NULL
	,InsideExecBrackets     BIT NOT NULL
	,IsPartOfBlockComment	BIT NOT NULL
	,IsCommented			BIT NOT NULL
	,DatabaseScope			VARCHAR(50) NOT NULL
)
AS
BEGIN
	DECLARE
		-- Current char position in examined destination code (@definitionCode parameter)
		@currentCharIndex INT = 1
		-- Chars indicating newline in examined code
		,@newlineChars CHAR(2) = CHAR(13)+CHAR(10)
		-- Position of next occurence of newline characters (counted from the beginning of examined code)
		,@nextPosOfNewLine INT = 0
		-- Temporary variables for filling up the result table. Also used as a status variables for parsing algorithm
		,@lineContent NVARCHAR(MAX) = N''
		,@lineNumber INT = 1
		,@isPartOfString BIT = 0
		,@isDynamicSQLExecuted BIT = 0
		,@isPartOfBlockComment BIT = 0
		,@isCommented BIT = 0
		,@databaseScope VARCHAR(50)

	-- Variables for parsing particular single lines of code
	DECLARE
		-- Current position in current examined line/subline
		@currLineIdx INT = 1
		-- Current position in current examined line/subline - measured from the beginning of original particular line of @definitionCode
		,@currLineIdxABS INT = 1
		-- Current char of examined line/subline
		,@currLineChar NCHAR(1) = N''
		-- For storing part of examined code, from start to the given char index. Needed when checking if particular plain string is an argument
		-- for EXEC or EXECUTE function
		,@codePartToGivenIdx VARCHAR(MAX) = N''
		-- For storing part of examined code, from given char index to the end. Needed when checking if particular apostrophe is an end of plain string
		,@codePartFromGivenIdx VARCHAR(MAX) = N''
		-- Counter for start-of-block-comment characters - for checking if block comment is ended or not
		,@noOfBlockCommentChars INT = 0
		-- Var for indicating if current code is between EXEC or EXECUTE function's brackets
		,@isInsideExecBrackets BIT = 0
		-- Var for indicating that this particular part of expression calculating dynamic T-SQL will be commented (in-line) when executed
		,@isDynamicSQLInLineCommented BIT = 0
		-- Var for indicating that this particular part of expression calculating dynamic T-SQL will be commented (block) when executed
		,@isDynamicSQLBlockCommented BIT = 0
		
	WHILE @currentCharIndex <= datalength(@definitionCode)/2
	BEGIN
		-- Get another line - from current point to the next CHAR(13)+CHAR(10)
		SET @nextPosOfNewLine = CHARINDEX(@newlineChars, @definitionCode, @currentCharIndex)
		SET @lineContent = CASE @nextPosOfNewLine 
								WHEN 0 THEN SUBSTRING(@definitionCode, @currentCharIndex, datalength(@definitionCode)/2 - @currentCharIndex + 1)  
								ELSE		SUBSTRING(@definitionCode, @currentCharIndex, @nextPosOfNewLine - @currentCharIndex) 
							END
		-- Extract characteristic parts of the code line indicated by the columns of result table
		-- Parse current line content and update status variables
		SELECT @currLineIdx = 1, @currLineIdxABS = 1 -- Initialize char index counters
				,@isCommented = 0 -- beginning of new line end in-line comment
				-- New line that occurs inside dynamic SQL ends its inline comments; when occurs outside - doesn't have impact 
				,@isDynamicSQLInLineCommented = CASE @isDynamicSQLExecuted WHEN 1 THEN 0 ELSE @isDynamicSQLInLineCommented END
		WHILE @currLineIdx <= datalength(@lineContent)/2
			BEGIN
				SET @currLineChar = SUBSTRING(@lineContent, @currLineIdx, 1)

				-- Start of case, when apostrophe character occurs
				IF @currLineChar = ''''
				BEGIN
					-- Case when apostrophe occurs and it is not part of other plain string or any type of comment
					IF @isPartOfString | @isPartOfBlockComment | @isCommented = 0 
					BEGIN
						-- This is start of new plain string. Insert into result table the part of this code line before the apostrophe
						IF @currLineIdx > 1 
							INSERT INTO @informationTable  
										VALUES 
											(@lineNumber
											,LEFT(@lineContent, @currLineIdx - 1) -- Enter line content excluding current character
											,@isPartOfString
											,@isDynamicSQLExecuted
											,@isInsideExecBrackets
											,@isPartOfBlockComment
											,@isCommented
											,'startofstring')
				
						-- Indicate that this is start of plain string
						SET @isPartOfString = 1
						-- In case when this is a part of expression which evaluates to dyanmic SQL string, and the previous part
						-- of the string ended with in-line comment without newline characters, indicate that it is commented
						SET @isCommented = CASE @isDynamicSQLInLineCommented WHEN 1 THEN 1 ELSE 0 END
						-- Check if this is an argument for EXEC or EXECUTE function - check if first signs beofore apostrophe are 'EXEC(' or 'EXECUTE('
						-- Spaces, tabs, carriage returns and line feeds are removed. Checking if result string starts with 'EXECUTE(' or  'EXEC('
						-- Also it is part of dynamic SQL, when it is inside EXEC brackets - when there is an expression which evaluates to string
						SET @codePartToGivenIdx = SUBSTRING(@definitionCode, 1, @currentCharIndex + @currLineIdxABS - 2)
						SET @codePartToGivenIdx = REPLACE(REPLACE(REPLACE(REPLACE(@codePartToGivenIdx, ' ', ''), CHAR(9), ''), CHAR(10), ''), CHAR(13), '')

						IF RIGHT(@codePartToGivenIdx collate Latin1_General_CI_AI, 5) ='EXEC(' 
							OR RIGHT(@codePartToGivenIdx collate Latin1_General_CI_AI, 8) = 'EXECUTE('
							OR @isInsideExecBrackets = 1
								SELECT 
									@isDynamicSQLExecuted = 1
									,@isInsideExecBrackets = 1

						-- Define the @lineContent as the rest of the line and initialize @currLineIdx again
						-- Important to put this after setting variable @codePartToGivenIdx . This statement below manipulates the value of @currLineIdx
						SELECT 
							@lineContent = RIGHT(@lineContent, datalength(@lineContent)/2 - @currLineIdx + 1)
							-- Set idx to the second character of line since all line content before EXCLUDING current character was entered into result table
							,@currLineIdx = 2 
							,@currLineIdxABS += 1
					END
					-- End of case when apostrophe is a start of new plain string
					-- Case when apostrophe occurs and it is part of other plain string. 
					ELSE IF (@isPartOfString = 1 AND @isPartOfBlockComment | @isCommented = 0)
							OR
							(@isPartOfString = 1 AND @isCommented = 1 AND @isDynamicSQLInLineCommented = 1)
					BEGIN
						-- Checking if this is end of plain string. 
						-- This is end only if next character, that is not a space, carriage return, line feed or tab, is not an apostrophe
						SET @codePartFromGivenIdx = SUBSTRING(@definitionCode, @currentCharIndex + @currLineIdxABS, datalength(@definitionCode)/2 - (@currentCharIndex + @currLineIdxABS)+1)
						SET @codePartFromGivenIdx = REPLACE(REPLACE(REPLACE(REPLACE(@codePartFromGivenIdx, ' ', ''), CHAR(9), ''), CHAR(10), ''), CHAR(13), '')
					
						-- Start of case when apostrophe is an end of plain string
						IF LEFT(@codePartFromGivenIdx, 1) != ''''
						BEGIN
							-- Update result table. Enter LineContent including current character
							INSERT INTO @informationTable  
								VALUES 
									(@lineNumber
									,LEFT(@lineContent, @currLineIdx) -- Enter Line Content including current character
									,@isPartOfString
									,@isDynamicSQLExecuted
									,@isInsideExecBrackets
									,@isPartOfBlockComment
									,@isCommented
									,'endofstring')

							-- Indicate that this is end of string
							SELECT 
								@isPartOfString = 0
								,@isDynamicSQLExecuted = 0
								,@isCommented = 0 -- In case when it was a dynamic SQL executed string and it ended with in-line comment
						
							-- Define the @lineContent as the rest of the line and initialize @currLineIdx again
							SELECT 
								@lineContent = RIGHT(@lineContent, datalength(@lineContent)/2 - @currLineIdx)
								,@currLineIdx = 1
								,@currLineIdxABS += 1
						END
						-- End of case when apostrophe is an end of plain string
					END
					-- End of case when apostrophe is a part of other plain string	
					-- When apostrophe was not functional - just increase char index counters
					ELSE 
						SELECT @currLineIdxABS += 1, @currLineIdx += 1
				END
				-- End of case when apostrophe character occurs
				-- Start of case when ')' occurs
				ELSE IF @currLineChar = ')'
				BEGIN
					-- Check if this is closing bracket of EXECUTE function running dynamic SQL code
					IF (@isPartOfString | @isPartOfBlockComment | @isCommented) = 0 AND (@isDynamicSQLExecuted | @isInsideExecBrackets = 1)
					BEGIN
						-- This is closing bracket of EXECUTE function running dynamic SQL code
						IF @currLineIdx > 1
							INSERT INTO @informationTable  
								VALUES 
									(@lineNumber
									,LEFT(@lineContent, @currLineIdx - 1) -- Enter line content excluding current character
									,@isPartOfString
									,@isDynamicSQLExecuted
									,@isInsideExecBrackets
									,@isPartOfBlockComment
									,@isCommented
									,'endofexec')

						-- Indicate that this is no longer dynamic SQL and no longer inside EXEC brackets
						SELECT 
							@isDynamicSQLExecuted = 0
							,@isInsideExecBrackets = 0
							-- Define the @lineContent as the rest of the line and initialize @currLineIdx again
							,@lineContent = RIGHT(@lineContent, datalength(@lineContent)/2 - @currLineIdx + 1)
							-- Set idx to the second character of line since all line content before EXCLUDING current character was entered into result table
							,@currLineIdx = 2
							-- Set absolute IDX to the next character, so ABS index points to the same char in original code line as the relative index in new subline
							,@currlineIdxABS += 1
					END
					-- End of case when ')' is a closing bracket of EXECUTE function running dynamic SQL code
					-- If this wasn't closig bracket of 'EXEC' function, just increase indexes
					ELSE
						SELECT  @currLineIdx += 1, @currlineIdxABS += 1
				END
				-- End of case when ')' occurs
				-- Start of case when '/*' occurs.
				ELSE IF @currLineChar = '/' AND SUBSTRING(@lineContent, @currLineIdx + 1, 1) = '*'
				BEGIN
					-- Case when '/*' are functional , either:
					-- not part of inline comment or plain string which is not dynamic SQL
					-- not part of inline comment and part of plain string whih is dynmaic SQL
					IF (@isPartOfString | @isDynamicSQLExecuted | @isCommented = 0 ) OR (@isPartOfString & @isDynamicSQLExecuted = 1 AND @isCommented = 0)
					BEGIN			
						-- If this is start of block comment, enter to the result table the conent before it
						IF @currLineIdx > 1 AND @isPartOfBlockComment = 0 
						BEGIN
							INSERT INTO @informationTable  
								VALUES 
									(@lineNumber
									,LEFT(@lineContent, @currLineIdx - 1) -- Enter lineContent excluding current character
									,@isPartOfString
									,@isDynamicSQLExecuted
									,@isInsideExecBrackets
									,@isPartOfBlockComment
									,@isCommented
									,'startofblock')
							-- Define the @lineContent as the rest of the line and initialize @currLineIdx again
							SELECT 
								@lineContent = RIGHT(@lineContent, datalength(@lineContent)/2 - @currLineIdx + 1) 
								,@currLineIdx = 3 -- Set the index behind '/*' characters that are already in the beginning of remaining part of current line
								,@currLineIdxABS += 2
						END
						-- If this characters are functional, but it wasn't start of new comment block, increase current indexes by 2.
						ELSE
							SELECT @currLineIdx += 2, @currLineIdxABS += 2
						-- End of case when this is start of block comment
						-- Indicate that it is block comment if it wasn't indicated before
						SET @isPartOfBlockComment = 1
						-- Increase counter of '/*' encountered
						SET @noOfBlockCommentChars += 1		
					END
					-- End of case when '/*' are functional - not part of inline comment and plain string
					-- If '/*' are NOT functional - just increase current line indexes by 1
					ELSE
						SELECT @currLineIdx += 1, @currLineIdxABS += 1
				END
				-- End of case when '/*' occurs. 
				-- Start of case when '*/' occurs
				ELSE IF @currLineChar = '*' AND SUBSTRING(@lineContent, @currLineIdx + 1, 1) = '/'
				BEGIN
					-- Case when '/*' are functional , either:
					-- not part of inline comment or plain string which is not dynamic SQL
					-- not part of inline comment and part of plain string whih is dynmaic SQL
					IF (@isPartOfString | @isDynamicSQLExecuted | @isCommented = 0 ) OR (@isPartOfString & @isDynamicSQLExecuted = 1 AND @isCommented = 0)
					BEGIN
						-- Decrease counter of block-comment characters
						SET @noOfBlockCommentChars -= 1
						-- Start of case, when counter value is zero and it was a block commnet until now
						IF @noOfBlockCommentChars = 0 AND @isPartOfBlockComment = 1
						BEGIN
							-- Set the current indexes to point to '/' character, not '*'
							SELECT @currLineIdx += 1, @currLineIdxABS += 1
							-- Update result table. Enter LineContent including current character
							INSERT INTO @informationTable  
								VALUES 
									(@lineNumber
									,LEFT(@lineContent, @currLineIdx) -- Enter LineContent including current character
									,@isPartOfString
									,@IsDynamicSQLExecuted
									,@isInsideExecBrackets
									,@isPartOfBlockComment
									,@isCommented
									,'endofblock')
						
							-- Define the @lineContent as the rest of the line and initialize @currLineIdx(ABS) again
							SELECT 
								@lineContent = RIGHT(@lineContent, datalength(@lineContent)/2 - @currLineIdx) 
								,@currLineIdx = 1
								,@currLineIdxABS += 1
								,@isPartOfBlockComment = 0 -- Indicate that this is no loger block comment
						END
						-- End of case, when counter value is zero and it was a block commnet until now
						-- If this signs are functional, but it wasn't end of block increase current indexes by 2
						ELSE
							SELECT @currLineIdx += 2, @currLineIdxABS += 2
					END
					-- End of case when '*/' are functional - not part of inline comment and plain string
					-- If '/*' are NOT functional - just increase current line indexes by 1
					ELSE
						SELECT @currLineIdx += 1, @currLineIdxABS += 1
				END
				-- End of case when '*/' occurs.
				-- Start of case when '--' occurs 
				IF @currLineChar = '-' AND SUBSTRING(@lineContent, @currLineIdx + 1, 1) = '-'
				BEGIN
					-- Case when '--' is functional - beginning of in-line comment
					IF (@isPartOfString | @isPartOfBlockComment | @isCommented = 0)
						OR
					   (@isPartOfString & @isDynamicSQLExecuted = 1 AND @isPartOfBlockComment | @isCommented = 0)
					BEGIN
						-- Case when this is outside of dynamic SQL expression
						IF @isPartOfString | @isPartOfBlockComment | @isCommented = 0
						BEGIN
							-- Insert in result table 2 rows - with all the content before '--' and all the content after '--' 
							IF @currLineIdx > 1 
								INSERT INTO @informationTable  
									VALUES 
										(@lineNumber
										,LEFT(@lineContent, @currLineIdx - 1) -- Enter line content before current character
										,@isPartOfString
										,@isDynamicSQLExecuted
										,@isInsideExecBrackets
										,@isPartOfBlockComment
										,@isCommented
										,'start_of_inline_comment')

							SELECT @isCommented = 1
								
							INSERT INTO @informationTable  
								VALUES 
									(@lineNumber
									,RIGHT(@lineContent, datalength(@lineContent)/2 - @currLineIdx + 1) -- Enter line content from current character to the end
									,@isPartOfString
									,@isDynamicSQLExecuted
									,@isInsideExecBrackets
									,@isPartOfBlockComment
									,@isCommented
									,'inline comment to the end')

							SELECT @currLineIdx = datalength(@lineContent)/2 + 1
						END
						--Case When this is inside of dynamic SQL expression
						ELSE IF @isPartOfString & @isDynamicSQLExecuted = 1 AND @isPartOfBlockComment | @isCommented = 0
						BEGIN
							-- Insert in result table 2 rows - with all the content before '--' and all the content after '--' 
							IF @currLineIdx > 1 
								INSERT INTO @informationTable  
									VALUES 
										(@lineNumber
										,LEFT(@lineContent, @currLineIdx - 1) -- Enter line content before current character
										,@isPartOfString
										,@isDynamicSQLExecuted
										,@isInsideExecBrackets
										,@isPartOfBlockComment
										,@isCommented
										,'start_of_inline_comment') 
							SELECT 
								@lineContent = RIGHT(@lineContent, datalength(@lineContent)/2 - @currLineIdx + 1) 
								,@currLineIdx = 3 -- Set the index behind '--' characters that are already in the beginning of remaining part of current line
								,@currLineIdxABS += 2
								,@isCommented = 1, @isDynamicSQLInLineCommented = 1
						END
					END
					-- End of case when '--' is functional 
					-- If '--' are NOT functional - just increase current line indexes by 1
					ELSE
						SELECT @currLineIdx += 1, @currLineIdxABS += 1
				END
				-- Case when other characters occurs
				ELSE
					SELECT @currLineIdx += 1, @currLineIdxABS += 1
			END
			-- End of loop which iterates through particular line of code
		
			-- Enter information about the rest of examined code line to the result table
			INSERT INTO @informationTable  
						VALUES 
							(@lineNumber
							,@lineContent -- Enter line comment including current character
							,@isPartOfString
							,@isDynamicSQLExecuted
							,@isInsideExecBrackets
							,@isPartOfBlockComment
							,@isCommented
							,'default')
		
			-- Next starting position is after [CHAR(13) and CHAR(10)] detected
			SELECT 
				@currentCharIndex = CASE @nextPosOfNewLine WHEN 0 THEN datalength(@definitionCode)/2 + 1 ELSE @nextPosOfNewLine + 2 END
				,@lineNumber += 1		
	END
	-- End of loop which iterates through all code definition (extracts lines)

	RETURN
END