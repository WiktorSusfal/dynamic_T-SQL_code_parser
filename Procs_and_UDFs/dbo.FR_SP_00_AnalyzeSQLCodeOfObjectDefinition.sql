-- =============================================
-- Author:		Wiktor Susfał
-- Create date: <Create Date,,>
-- Description:	Procedure for managing the process of analyzing definition code of given database object
-- =============================================
CREATE PROCEDURE [dbo].[FR_SP_00_AnalyzeSQLCodeOfObjectDefinition]
	-- IF 'Y' then procedure extracts the definition code from relevant system view. If 'N' then it expects the code to be given in parameter '@objectDefinition'
	@codeGivenByObjectName CHAR = 'Y'
	-- IF 'Y' then given object is a SQL job, otherwise not
	,@isSQLJob CHAR = 'N'
	-- Parts of full name of destination object which definition code is to be examined. Can be quoted or not;
	-- IF @isSQLJob CHAR = 'Y' then not used
	,@objectDatabaseName VARCHAR(50) = NULL
	,@objectSchemaName VARCHAR(50) = NULL
	-- IF @isSQLJob = 'N' then it stands for regular object name from database, 
	-- IF @isSQLJob = 'Y' then it stands for SQL JOB Name
	,@objectName VARCHAR(100) = NULL
	-- Used when @isSQLJob = 'Y', stands for name of the job step
	,@jobStepName VARCHAR(100) = NULL
	-- Object definition code in case the '@codeGivenByObjectName' parameter = 'Y'
	,@objectDefinition NVARCHAR(MAX) = NULL

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	BEGIN TRY

		-- Retrieve the definition code of destination object in proper way
		DECLARE @definitionCode NVARCHAR(MAX) = N''

		-- If database and schema names are needed and hasn't been provided
		IF UPPER(@codeGivenByObjectName) = 'Y' AND UPPER(@isSQLJob) = 'N'
		   AND (ISNULL(@objectDatabaseName, '') = '' OR ISNULL(@objectSchemaName, '') = '')
				RAISERROR ('@objectDatabaseName and @objectSchemaName must be specified!', 16, 1);  

		IF UPPER(@codeGivenByObjectName) = 'N'
			SET @definitionCode = @objectDefinition
		ELSE IF UPPER(@codeGivenByObjectName) = 'Y' AND UPPER(@isSQLJob) = 'N'
		BEGIN
			EXECUTE FR_APP.dbo.FR_SP_01_ReturnObjectDefinition 
				@objectDatabaseName = @objectDatabaseName
				,@objectSchemaName = @objectSchemaName
				,@objectName  = @objectName
				,@definition  = @definitionCode OUTPUT

			IF ISNULL(@definitionCode, N'') = N''
				RAISERROR('Empty definition code of destination object! Procedure aborted!', 16, 1);
		END
		-- If given object is SQL job step:
		ELSE IF UPPER(@codeGivenByObjectName) = 'Y' AND UPPER(@isSQLJob) = 'Y'
		BEGIN
			DECLARE @typeOfJobStep VARCHAR(25) = N''
			
			SELECT 
				@typeOfJobStep = sjs.subsystem -- must be 'TSQL' for this procedure
				,@definitionCode = sjs.command
			FROM msdb.dbo.sysjobs sj
			INNER JOIN msdb.dbo.sysjobsteps sjs ON sj.job_id = sjs.job_id
			WHERE 
				sj.[name] = @objectName
				AND sjs.step_name = @jobStepName

			IF ISNULL(@definitionCode, N'') = N''
				RAISERROR('Empty definition code of destination job step! Procedure aborted!', 16, 1);
			IF ISNULL(@typeOfJobStep, '') != 'TSQL'
				RAISERROR('Wrong type of job step given! Must be ''TSQL''!', 16, 1);
		END
		ELSE
			RAISERROR ('Wrong value for parameter @codeGivenByObjectName or @isSQLJob. Please specify ''Y'' or ''N''!', 16, 1);
		-- End of retrieving definition code of destination object 

		-- Invoke the main parsing table-valued function to return description of examined SQL code in form of table
		SELECT 
			TableKey
			,LineNumber
			,LineContent
			,IsPartOfRegularString
			,IsDynamicSQLExecuted
			,InsideExecBrackets
			,IsPartOfBlockComment
			,IsCommented	
		FROM dbo.FR_TVF_00_ParseDefinitionCode(@definitionCode)

	END TRY
	BEGIN CATCH
		DECLARE @errMsg NVARCHAR(300) = ERROR_MESSAGE()
		RAISERROR(@errMsg, 16, 1)
	END CATCH
END