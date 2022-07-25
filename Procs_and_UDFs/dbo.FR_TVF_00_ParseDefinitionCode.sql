-- =============================================
-- Author:		Wiktor Susfa³
-- Create date: <Create Date,,>
-- Description:	Table function to parse given source code to table (line by line). Each record refers to particular line (or part of the line) of code. 
--				Basically, when value of any variable describing the content of code changes, new information is stored in separate row. Rows contains info of:
				-- -TableKey				INT - autoincremental key - counter for rows in output table
				-- -LineNumber				INT - number of line in original code where the content stored in 'LineContent' column was found
				-- -LineContent				NVARCHAR(MAX) - content of single line of original code (or part of single line) that can be described by the values in following columns 
				-- -IsPartOfRegularString	BIT - if '1' and IsDynamicSQLExecuted = '0' then the 'LineContent' is a part of plain string written outside of the EXEC function brackets
				-- -IsDynamicSQLExecuted	BIT - if '1' and IsPartOfRegularString = '0' then the 'LineContent' is a string that represents code that is being executed inside EXEC functions of this procedure;
				--								- if '1' and IsPartOfRegularString = '1' then the 'LineContent' is a string that represents plain string that is a part of dynamic SQL code
				-- -InsideExecBrackets      BIT - if '1' then the 'LineContent' is inside EXEC brackets
				-- -IsPartOfBlockComment	BIT - if '1' then the 'LineContent' is a part of block comment. If IsPartOfRegularString = 0 and  IsDynamicSQLExecuted = 0 then the block comment is at the main level of code executed;
				--								- if IsDynamicSQLExecuted = 1 then 'LineContent' is a part of block comments in dynamic SQL execudet inside code examined
				-- -IsCommented				BIT - indicate if 'LineContent' is a part of in-line comment (--). The dependencies on 'IsPartOfRegularString'	and 'IsDynamicSQLExecuted' are the same as above
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
	,IsPartOfRegularString	BIT NOT NULL
	,IsDynamicSQLExecuted	BIT NOT NULL
	,InsideExecBrackets     BIT NOT NULL
	,IsPartOfBlockComment	BIT NOT NULL
	,IsCommented			BIT NOT NULL
)
AS
BEGIN
	DECLARE
		-- Temporary variables for filling up the result table. Also used as a status variables for parsing algorithm
		@lineNumber INT = 1
		,@lineContent NVARCHAR(MAX) = N''
		,@isPartOfRegularString BIT = 0
		,@isDynamicSQLExecuted BIT = 0
		,@isInsideExecBrackets BIT = 0
		,@isPartOfBlockComment BIT = 0
		,@isCommented BIT = 0
		-- Variables used only during parsing source code
		,@currentCharIndex INT = 1					-- Current char position in examined definition code (@definitionCode parameter)
		,@newlineChars CHAR(2) = CHAR(13)+CHAR(10)	-- Chars indicating newline in examined code
		,@nextPosOfNewLine INT = 0 					-- Position of next occurence of newline characters (counted from the beginning of examined code)	
		,@currLineIdx INT = 1						-- Current position in current examined line/subline. Re-initialized always when splitting up the line
		,@currLineIdxABS INT = 1					-- Current position in current examined line - measured from the beginning of original particular line of @definitionCode		
		,@currLineChar NCHAR(1) = N''				-- Current char of examined line/subline
		,@prevLineChar NCHAR(1) = N''				-- Previous char of examined lin/subline
		,@nextLineChar NCHAR(1) = N''				-- Next char of examined line/subline
		,@codePartToGivenIdx VARCHAR(MAX) = N''		-- Part of original examined code, from start to the given char index; e.g. for checking if particular plain string is an argument of EXEC
		,@codePartFromGivenIdx VARCHAR(MAX) = N''	-- Part of original examined code, from given char index to the end; e.g for checking if particular apostrophe is an end of plain string
		,@noOfBlockCommentChars INT = 0             -- Counter for start-of-block-comment characters - for checking if block comment is ended or not
		,@noOfBlockCommentCharsDynamicSQL INT = 0	-- Counter for start-of-block-comment characters inside dynamic SQL code - for checking if block comment is ended or not
		,@isDynamicSQLInLineCommented BIT = 0		-- Indicating that this particular part of expression calculating dynamic T-SQL will be commented (in-line) when executed
		,@isDynamicSQLRegularString BIT = 0			-- Indicating that thisthis particular part of expression calculating dynamic T-SQL will be a regular string when executed
		,@isBehindExecuteKeyword BIT = 0			-- Indicating that the code is behind execute keyword 
	
	-- Main loop to iterate through original source code, extract its lines and parse them
	WHILE @currentCharIndex <= datalength(@definitionCode)/2
	BEGIN
		-- Get another line of code - from current point to the next CHAR(13)+CHAR(10)
		SET @nextPosOfNewLine = CHARINDEX(@newlineChars, @definitionCode, @currentCharIndex)
		SET @lineContent = CASE @nextPosOfNewLine
								-- When there is no newline, use the content from this index to the end
								WHEN 0 THEN SUBSTRING(@definitionCode, @currentCharIndex, datalength(@definitionCode)/2 - @currentCharIndex + 1)  
								ELSE		SUBSTRING(@definitionCode, @currentCharIndex, @nextPosOfNewLine - @currentCharIndex) 
							END
		
		SELECT @currLineIdx = 1, @currLineIdxABS = 1 -- Initialize char index counters before looping through next code line
				,@isCommented = 0 -- beginning of new line end in-line comment in non-dynamic SQL code
				-- New line that occurs inside dynamic SQL ends its inline comments; when occurs outside - doesn't have impact 
				,@isDynamicSQLInLineCommented = CASE @isDynamicSQLExecuted WHEN 1 THEN 0 ELSE @isDynamicSQLInLineCommented END

		-- Loop to extract characteristic parts of the code line and indicate them by the columns of result table
		WHILE @currLineIdx <= datalength(@lineContent)/2
		BEGIN
			SELECT	@currLineChar	= SUBSTRING(@lineContent, @currLineIdx, 1)
					,@prevLineChar  = SUBSTRING(@lineContent, @currLineIdx - 1, 1)
					,@nextLineChar  = SUBSTRING(@lineContent, @currLineIdx + 1, 1)

			-- List of conditions and actions for cases when particular characteristic chars are found
			-- Start of case, when apostrophe character occurs
			IF @currLineChar = ''''
			BEGIN
				-- Case when apostrophe starts new plain string at the main level of code - it is not part of other plain string or any type of comment
				IF @isPartOfRegularString | @isDynamicSQLExecuted | @isPartOfBlockComment | @isCommented = 0
				BEGIN
					-- Insert into result table the part of this code line before the apostrophe. If this is NVARCHAR - treat the 'N' as a part of string, not the content before
					IF @currLineIdx > CASE @prevLineChar collate Latin1_General_CI_AI WHEN 'N' THEN 2 ELSE 1 END 
						INSERT INTO @informationTable  
									VALUES 
										(@lineNumber
										,LEFT(@lineContent, CASE @prevLineChar collate Latin1_General_CI_AI
																WHEN 'N' THEN @currLineIdx - 2
																ELSE @currLineIdx - 1
															END) -- Enter line content before string detected
										,@isPartOfRegularString
										,@isDynamicSQLExecuted
										,@isInsideExecBrackets
										,@isPartOfBlockComment
										,@isCommented)
					
					-- Check if this is part of dynamic SQL - an argument for EXEC or EXECUTE function - check if it is inside EXEC brackets
					IF @isInsideExecBrackets = 1
						SELECT 
							@isDynamicSQLExecuted = 1
							-- In case this is a part of expression evaluated to dyanmic SQL, and the previous part of the string ended with in-line comment without newline characters, 
							-- indicate that it is commented
							,@isCommented =				CASE @isDynamicSQLInLineCommented		WHEN 1 THEN 1 ELSE 0 END
							,@isPartOfRegularString =	CASE @isDynamicSQLRegularString			WHEN 1 THEN 1 ELSE 0 END
							,@isPartOfBlockComment =	CASE @noOfBlockCommentCharsDynamicSQL	WHEN 0 THEN 0 ELSE 1 END
					ELSE
						SET @isPartOfRegularString = 1

					-- Define the @lineContent as the rest of the line (starting from ' or N') and update line char indexes
					-- Important to put this after setting variable @codePartToGivenIdx . This statement below manipulates the value of @currLineIdx
					SELECT 
						@lineContent = RIGHT(@lineContent, datalength(@lineContent)/2 - @currLineIdx + CASE @prevLineChar collate Latin1_General_CI_AI
																											WHEN 'N' THEN 2
																											ELSE 1
																										END)
						-- Set idx to the character  after ' or N'
						,@currLineIdx = CASE @prevLineChar collate Latin1_General_CI_AI WHEN 'N' THEN 3 ELSE 2 END
						,@currLineIdxABS += 1
				END
				-- End of case when apostrophe starts new plain string at the main level of code - it is not part of other plain string or any type of comment
				-- Case when apostrophe occurs, it is part of other plain string and it ends this string
				-- Single apostrophe cannot occur is string without ending it
				ELSE IF (@isPartOfRegularString | @isDynamicSQLExecuted = 1 AND @nextLineChar != '''')
				BEGIN
					-- Update result table. Enter LineContent including current character
					INSERT INTO @informationTable  
						VALUES 
							(@lineNumber
							,LEFT(@lineContent, @currLineIdx) -- Enter Line Content including current character
							,@isPartOfRegularString
							,@isDynamicSQLExecuted
							,@isInsideExecBrackets
							,@isPartOfBlockComment
							,@isCommented)

					-- If this string was a part of dynamic SQL, and it ended in the middle of in-line comment or regular string, indicate properly
					SELECT
						@isDynamicSQLInLineCommented	= CASE @isCommented										WHEN 1 THEN 1 ELSE 0 END
						,@isDynamicSQLRegularString		= CASE @isPartOfRegularString & @isDynamicSQLExecuted	WHEN 1 THEN 1 ELSE 0 END 
					-- Indicate that this is end of string
					SELECT 
						@isPartOfRegularString = 0
						,@isDynamicSQLExecuted = 0
						,@isCommented = 0 -- In case when it was a dynamic SQL executed string and it ended with in-line comment
					-- Define the @lineContent as the rest of the line and initialize @currLineIdx again
					SELECT 
						@lineContent = RIGHT(@lineContent, datalength(@lineContent)/2 - @currLineIdx)
						,@currLineIdx = 1
						,@currLineIdxABS += 1
				END
				-- End of case when apostrophe occurs and it ends a string
				-- Case when apostrophe occurs inside of regular string and desn't end it  or inside of comments placed inside of dynamic SQL 
				ELSE IF (@isPartOfRegularString = 1 AND @isDynamicSQLExecuted = 0 AND @nextLineChar = '''')
						OR
						(@isDynamicSQLExecuted = 1 AND @isCommented | @isPartOfBlockComment = 1)
				BEGIN
					-- Increase indexes by 2 - to skip (''), to not false recognize the second ' as end of the string
					SELECT
						@currLineIdx += 2
						,@currLineIdxABS += 2
				END
				-- End of case when apostrophe occurs inside of regular string and desn't end it
				-- Case when apostrophe occurs inside of regular string inside of dynamic SQL and it doesnt end it
				ELSE IF  @isPartOfRegularString = 1 AND @isDynamicSQLExecuted = 1 AND @nextLineChar = '''' AND SUBSTRING(@lineContent, @currLineIdx + 2, 2) = ''''''
				BEGIN
					-- Increase indexes by 4 - to skip (''''), to not false recognize the second pair of ' as end of the string inside dynamic SQL
					SELECT
						@currLineIdx += 4
						,@currLineIdxABS += 4
				END
				-- End of case  when apostrophe occurs inside of regular string inside of dynamic SQL and it doesnt end it
				-- Case when apostrophe occurs inside of dynamic SQL code and starts a regular string is not a part of any comments in dynamic SQL
				ELSE IF (@isPartOfRegularString = 0 AND @isDynamicSQLExecuted = 1 AND @nextLineChar = '''') AND  (@isPartOfBlockComment | @isCommented) = 0
				BEGIN
					-- Insert into result table the part of this code line before the apostrophe. If this is NVARCHAR - treat the 'N' as a part of string, not the content before
					IF @currLineIdx > CASE @prevLineChar collate Latin1_General_CI_AI WHEN 'N' THEN 2 ELSE 1 END 
						INSERT INTO @informationTable  
							VALUES 
								(@lineNumber
								,LEFT(@lineContent, CASE @prevLineChar collate Latin1_General_CI_AI
														WHEN 'N' THEN @currLineIdx - 2
														ELSE @currLineIdx - 1
													END) -- Enter line content before string detected
								,@isPartOfRegularString
								,@isDynamicSQLExecuted
								,@isInsideExecBrackets
								,@isPartOfBlockComment
								,@isCommented)

					-- Define the @lineContent as the rest of the line (starting from ' or N') and update line char indexes
					SELECT 
						@lineContent = RIGHT(@lineContent, datalength(@lineContent)/2 - @currLineIdx + CASE @prevLineChar collate Latin1_General_CI_AI
																											WHEN 'N' THEN 2
																											ELSE 1
																										END)
						-- Set idx to the character  after '' or N''
						,@currLineIdx = CASE @prevLineChar collate Latin1_General_CI_AI WHEN 'N' THEN 4 ELSE 3 END
						,@currLineIdxABS += 2
						-- Indicate that this is start of regular string inside dynamic SQL code
						,@isPartOfRegularString = 1
						,@isDynamicSQLRegularString = 1
				END
				-- Case when apostrophe occurs inside of dynamic SQL code and starts a regular string is not a part of any comments in dynamic SQL
				-- Case when apostrophe occurs inside of regular string inside of dynamic SQL code and ends it and is not a part of any comments in dynamic SQL
				ELSE IF @isPartOfRegularString = 1 AND @isDynamicSQLExecuted = 1 AND @nextLineChar = '''' AND SUBSTRING(@lineContent, @currLineIdx + 2, 2) != ''''''
				BEGIN
					INSERT INTO @informationTable  
						VALUES 
							(@lineNumber
							,LEFT(@lineContent, @currLineIdx + 1) -- Enter Line Content including current character and next character ('')
							,@isPartOfRegularString
							,@isDynamicSQLExecuted
							,@isInsideExecBrackets
							,@isPartOfBlockComment
							,@isCommented)

					-- Indicate that this is end of string inside dynamic SQL
					SELECT
						@isDynamicSQLRegularString = 0 
						,@isPartOfRegularString = 0
					-- Define the @lineContent as the rest of the line and initialize @currLineIdx again
					SELECT 
						@lineContent = RIGHT(@lineContent, datalength(@lineContent)/2 - @currLineIdx - 1)
						,@currLineIdx = 1
						,@currLineIdxABS += 2
				END
				-- End of case when apostrophe occurs inside of regular string inside of dynamic SQL code and ends it and is not a part of any comments in dynamic SQL
				ELSE
					SELECT @currLineIdx += 1, @currLineIdxABS += 1
			END
			-- End of case, when apostrophe character occurs
			-- Start of case when 'EXEC or EXECUTE' occurs
			ELSE IF @currLineChar collate Latin1_General_CI_AI = 'E' 
					AND @isPartOfRegularString | @isDynamicSQLExecuted | @isPartOfBlockComment | @isCommented = 0
					AND @prevLineChar IN ('', ' ', '''', ';', '"', ']') 
					AND SUBSTRING(@lineContent, @currLineIdx, 4) collate Latin1_General_CI_AI = 'EXEC'
			BEGIN
				-- Indicate that 'EXEC' or 'EXECUTE' keyword occured
				SELECT 
					@currLineIdx += CASE SUBSTRING(@lineContent, @currLineIdx, 7) collate Latin1_General_CI_AI WHEN 'EXECUTE' THEN 7 ELSE 4 END
					,@isBehindExecuteKeyword = 1
			END
			-- End of case when 'EXEC or EXECUTE' occurs
			-- Case when '(' char occurs and its opening bracket for EXEC or EXECUTE function
			ELSE IF @currLineChar = '('
					AND @isBehindExecuteKeyword = 1
					AND @isPartOfRegularString | @isDynamicSQLExecuted | @isPartOfBlockComment | @isCommented = 0
			BEGIN
				-- Insert into result table the content before '(' including '('
				INSERT INTO @informationTable  
					VALUES 
						(@lineNumber
						,LEFT(@lineContent, @currLineIdx) -- Enter line content including current character
						,@isPartOfRegularString
						,@isDynamicSQLExecuted
						,@isInsideExecBrackets
						,@isPartOfBlockComment
						,@isCommented)

				-- Indicate that this is opening bracket for EXECUTE or EXEC function
				SELECT 
					@isInsideExecBrackets = 1
					,@isBehindExecuteKeyword = 0
					-- Define the @lineContent as the rest of the line and initialize @currLineIdx again
					,@lineContent = RIGHT(@lineContent, datalength(@lineContent)/2 - @currLineIdx)
					-- Set idx to the first character of line since all line content before including current character was entered into result table
					,@currLineIdx = 1
					-- Set absolute IDX to the next character, so ABS index points to the same char in original code line as the relative index in new subline
					,@currlineIdxABS += 1
			END
			-- End of case when '(' char occurs and its opening bracket for EXEC or EXECUTE function
			-- Start of case when ')' occurs and it is closing bracket of EXECUTE function running dynamic SQL code
			ELSE IF @currLineChar = ')'
					AND (@isPartOfRegularString | @isDynamicSQLExecuted | @isPartOfBlockComment | @isCommented) = 0 
					AND @isInsideExecBrackets = 1
			BEGIN
				IF @currLineIdx > 1
					INSERT INTO @informationTable  
						VALUES 
							(@lineNumber
							,LEFT(@lineContent, @currLineIdx - 1) -- Enter line content excluding current character
							,@isPartOfRegularString
							,@isDynamicSQLExecuted
							,@isInsideExecBrackets
							,@isPartOfBlockComment
							,@isCommented)

				-- Indicate that this is no longer dynamic SQL and no longer inside EXEC brackets
				SELECT 
					@isInsideExecBrackets = 0
					-- Define the @lineContent as the rest of the line and initialize @currLineIdx again
					,@lineContent = RIGHT(@lineContent, datalength(@lineContent)/2 - @currLineIdx + 1)
					-- Set idx to the second character of line since all line content before EXCLUDING current character was entered into result table
					,@currLineIdx = 2
					-- Set absolute IDX to the next character, so ABS index points to the same char in original code line as the relative index in new subline
					,@currlineIdxABS += 1
			END
			-- End of case when ')' is a closing bracket of EXECUTE function running dynamic SQL code
			-- Start of case when '/*' occurs and are functional , either: not part of inline comment or plain string (either in both - dynamic SQL and regular SQL code
			ELSE IF @currLineChar = '/' AND @nextLineChar = '*'
					AND @isPartOfRegularString | @isCommented = 0
			BEGIN
				-- If this is start of block comment, enter to the result table the conent before it
				IF @currLineIdx > 1 AND @isPartOfBlockComment = 0 
				BEGIN
					INSERT INTO @informationTable  
						VALUES 
							(@lineNumber
							,LEFT(@lineContent, @currLineIdx - 1) -- Enter lineContent excluding current character
							,@isPartOfRegularString
							,@isDynamicSQLExecuted
							,@isInsideExecBrackets
							,@isPartOfBlockComment
							,@isCommented)
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
				-- Increase relevant counter of '/*' encountered
				IF @isDynamicSQLExecuted = 1
					SET @noOfBlockCommentCharsDynamicSQL += 1
				ELSE
					SET @noOfBlockCommentChars += 1		
			END
			-- End of case when '/*' occurs and are functional - not part of inline comment and plain string
			-- Start of case when '*/' occurs and are functional - not part of inline comment or plain string in both: dynamic and regular SQL
			ELSE IF @currLineChar = '*' AND @nextLineChar = '/'
					AND @isPartOfRegularString  | @isCommented = 0
			BEGIN
				-- Decrease relevant counter of block-comment characters
				IF @isDynamicSQLExecuted = 1
					SET @noOfBlockCommentCharsDynamicSQL -= 1
				ELSE
					SET @noOfBlockCommentChars -= 1
				-- Start of case, when counter value is zero and it was a block commnet until now
				IF ((@noOfBlockCommentChars = 0 AND @isDynamicSQLExecuted = 0) OR (@noOfBlockCommentCharsDynamicSQL = 0 AND @isDynamicSQLExecuted = 1))
					AND @isPartOfBlockComment = 1
				BEGIN
					-- Set the current indexes to point to '/' character, not '*'
					SELECT @currLineIdx += 1, @currLineIdxABS += 1
					-- Update result table. Enter LineContent including current character
					INSERT INTO @informationTable  
						VALUES 
							(@lineNumber
							,LEFT(@lineContent, @currLineIdx) -- Enter LineContent including current character
							,@isPartOfRegularString
							,@IsDynamicSQLExecuted
							,@isInsideExecBrackets
							,@isPartOfBlockComment
							,@isCommented)
						
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
			-- End of case when '*/' occurs and are functional - not part of inline comment and plain string
			-- Start of case when '--' occurs and are functional - beginning of in-line comment
			ELSE IF @currLineChar = '-' 
					AND @nextLineChar = '-'
					AND @isPartOfRegularString | @isPartOfBlockComment | @isCommented = 0
			BEGIN
				-- Insert in result table and all the content before '--'
				IF @currLineIdx > 1 
					INSERT INTO @informationTable  
						VALUES 
							(@lineNumber
							,LEFT(@lineContent, @currLineIdx - 1) -- Enter line content before current character
							,@isPartOfRegularString
							,@isDynamicSQLExecuted
							,@isInsideExecBrackets
							,@isPartOfBlockComment
							,@isCommented)
				
				-- Update line content variable and others
				SELECT 
					@lineContent = RIGHT(@lineContent, datalength(@lineContent)/2 - @currLineIdx + 1) 
					,@currLineIdx = 3 -- Set the index behind '--' characters that are already in the beginning of remaining part of current line
					,@currLineIdxABS += 2
					,@isCommented = 1
					,@isDynamicSQLInLineCommented = CASE @isDynamicSQLExecuted WHEN 1 THEN 1 ELSE 0 END
			END
			-- End of case when '--' occurs and are functional 
			-- Case when other characters occurs
			ELSE
			BEGIN
				-- If previously 'EXECUTE' function occured and now there is not commented character other that space, tab etc.. indicate that there are no EXEC bracked this time
				IF @isBehindExecuteKeyword = 1
					AND @isPartOfBlockComment | @isCommented = 0
					AND @currLineChar NOT IN (' ', CHAR(9), CHAR(10), CHAR(13), '(')
					-- Indicate that this time the EXEC was invoked without '()'
					SELECT
						@isBehindExecuteKeyword = 0
				-- Just increase the indexes
				SELECT @currLineIdx += 1, @currLineIdxABS += 1
			END
			-- End of case when other characters occurs
		END
		-- End of loop to extract characteristic parts of the code line and indicate them by the columns of result table
		-- Enter information about the rest of examined code line to the result table
		IF DATALENGTH(@lineContent) > 0
			INSERT INTO @informationTable  
						VALUES 
							(@lineNumber
							,@lineContent -- Enter line comment including current character
							,@isPartOfRegularString
							,@isDynamicSQLExecuted
							,@isInsideExecBrackets
							,@isPartOfBlockComment
							,@isCommented)

		-- Next starting position is after [CHAR(13) and CHAR(10)] detected
		SELECT 
			@currentCharIndex = CASE @nextPosOfNewLine WHEN 0 THEN datalength(@definitionCode)/2 + 1 ELSE @nextPosOfNewLine + 2 END
			,@lineNumber += 1		
	END
	-- End of main loop to iterate through original source code, extract its lines and parse them
	
	RETURN 
END
GO


