SET XACT_ABORT ON;
GO

IF OBJECT_ID(N'dbo.Users', N'U') IS NOT NULL
   AND COL_LENGTH(N'dbo.Users', N'CanViewReportProductProfit') IS NULL
BEGIN
    ALTER TABLE dbo.Users
        ADD CanViewReportProductProfit BIT NOT NULL
            CONSTRAINT DF_Users_CanViewReportProductProfit DEFAULT (0);
END;
GO

IF OBJECT_ID(N'dbo.Users', N'U') IS NOT NULL
   AND COL_LENGTH(N'dbo.Users', N'CanViewReportProductProfit') IS NOT NULL
BEGIN
    EXEC(N'
        UPDATE dbo.Users
        SET CanViewReportProductProfit = 1
        WHERE RoleId = 1
           OR LOWER(ISNULL(Username, N'''')) = N''admin'';
    ');
END;
GO
