IF OBJECT_ID(N'dbo.Users', N'U') IS NOT NULL
   AND COL_LENGTH(N'dbo.Users', N'CanViewReportRevenueProfit') IS NULL
BEGIN
    ALTER TABLE dbo.Users
        ADD CanViewReportRevenueProfit BIT NOT NULL
            CONSTRAINT DF_Users_CanViewReportRevenueProfit DEFAULT (0);
END;
GO

IF OBJECT_ID(N'dbo.Users', N'U') IS NOT NULL
   AND COL_LENGTH(N'dbo.Users', N'CanViewReportRevenueProfit') IS NOT NULL
BEGIN
    UPDATE dbo.Users
    SET CanViewReportRevenueProfit = 1
    WHERE RoleId = 1 OR LOWER(ISNULL(Username, N'')) = N'admin';
END;
GO
