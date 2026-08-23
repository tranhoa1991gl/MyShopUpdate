SET XACT_ABORT ON;
GO

IF OBJECT_ID(N'dbo.Users', N'U') IS NOT NULL
   AND COL_LENGTH(N'dbo.Users', N'CanViewReportCustomerProfit') IS NULL
BEGIN
    ALTER TABLE dbo.Users
        ADD CanViewReportCustomerProfit BIT NOT NULL
            CONSTRAINT DF_Users_CanViewReportCustomerProfit DEFAULT (0);
END;
GO

IF OBJECT_ID(N'dbo.Users', N'U') IS NOT NULL
   AND COL_LENGTH(N'dbo.Users', N'CanViewReportCustomerProfit') IS NOT NULL
BEGIN
    EXEC(N'
        UPDATE dbo.Users
        SET CanViewReportCustomerProfit = 1
        WHERE RoleId = 1
           OR LOWER(ISNULL(Username, N'''')) = N''admin'';
    ');
END;
GO
