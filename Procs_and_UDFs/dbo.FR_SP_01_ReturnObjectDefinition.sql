-- =============================================
-- Author:		Wiktor Susfał
-- Create date: <Create Date,,>
-- Description:	Procedure to return definition code of any object from any database - via output parameter. 
-- =============================================
CREATE PROCEDURE FR_SP_01_ReturnObjectDefinition 
	-- Add the parameters for the stored procedure here
	@objectDatabaseName VARCHAR(50) = NULL
	,@objectSchemaName VARCHAR(50) = NULL
	,@objectName VARCHAR(100) = NULL
	,@definition NVARCHAR(MAX) = NULL OUTPUT

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	-- Quote names of resources if not quoted
	DECLARE @quotedDatabaseName VARCHAR(52), @quotedSchemaName VARCHAR(52), @quotedObjectName VARCHAR(102)
	SELECT
		@quotedDatabaseName = dbo.FR_SVF_00_QuoteIfNotQuoted(@objectDatabaseName)
		,@quotedSchemaName	= dbo.FR_SVF_00_QuoteIfNotQuoted(@objectSchemaName)
		,@quotedObjectName	= dbo.FR_SVF_00_QuoteIfNotQuoted(@objectName)

	-- Declare template of SQL query with placeholders
	DECLARE @sqlQuery NVARCHAR(250) = 
		N'SELECT 
			@resultDefinition = [definition] 
		 FROM ++@quotedDatabaseName@++.[sys].[sql_modules]
		 WHERE 
			object_id = OBJECT_ID(''++@quotedDatabaseName@++.++@quotedSchemaName@++.++@quotedObjectName@++'')'

	DECLARE @paramDefinition NVARCHAR(50) = N'@resultDefinition NVARCHAR(MAX) OUTPUT'

	-- Replace placeholders with values in SQL query
	SET @sqlQuery = REPLACE(@sqlQuery, '++@quotedDatabaseName@++', @quotedDatabaseName)
	SET @sqlQuery = REPLACE(@sqlQuery, '++@quotedSchemaName@++', @quotedSchemaName)
	SET @sqlQuery = REPLACE(@sqlQuery, '++@quotedObjectName@++', @quotedObjectName)

	-- Calculate output
	EXECUTE sp_executesql @sqlQuery, @paramDefinition, @resultDefinition = @definition OUTPUT

	IF len(@definition) = 0 SET @definition = NULL 

END