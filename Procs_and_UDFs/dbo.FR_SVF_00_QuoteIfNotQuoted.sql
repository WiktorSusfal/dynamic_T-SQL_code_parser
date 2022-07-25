-- =============================================
-- Author:		Wiktor Susfał
-- Create date: <Create Date, ,>
-- Description:	<Description, ,>
-- =============================================
CREATE FUNCTION [dbo].[FR_SVF_00_QuoteIfNotQuoted]
(
	-- Add the parameters for the function here
	@string NVARCHAR(MAX)
)
RETURNS NVARCHAR(MAX)
AS
BEGIN
	-- Declare the return variable here
	DECLARE @result NVARCHAR(MAX);

	IF LEFT(@string, 1) = '[' AND RIGHT(@string, 1) = ']'
		SET @result =  @string;
	ELSE
		set @result = N'[' + @string + N']'

	RETURN @result;

END