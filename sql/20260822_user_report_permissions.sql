SET XACT_ABORT ON;

/*
   Phân quyền truy cập báo cáo theo tài khoản.
   Script an toàn khi chạy lại nhiều lần.
*/

IF OBJECT_ID(N'dbo.Users', N'U') IS NOT NULL
BEGIN
    IF COL_LENGTH(N'dbo.Users', N'CanViewReports') IS NULL
        ALTER TABLE dbo.Users ADD CanViewReports BIT NOT NULL CONSTRAINT DF_Users_CanViewReports DEFAULT (0);

    IF COL_LENGTH(N'dbo.Users', N'CanViewReportOverview') IS NULL
        ALTER TABLE dbo.Users ADD CanViewReportOverview BIT NOT NULL CONSTRAINT DF_Users_CanViewReportOverview DEFAULT (0);

    IF COL_LENGTH(N'dbo.Users', N'CanViewReportCollections') IS NULL
        ALTER TABLE dbo.Users ADD CanViewReportCollections BIT NOT NULL CONSTRAINT DF_Users_CanViewReportCollections DEFAULT (0);

    IF COL_LENGTH(N'dbo.Users', N'CanViewReportRevenue') IS NULL
        ALTER TABLE dbo.Users ADD CanViewReportRevenue BIT NOT NULL CONSTRAINT DF_Users_CanViewReportRevenue DEFAULT (0);

    IF COL_LENGTH(N'dbo.Users', N'CanViewReportProducts') IS NULL
        ALTER TABLE dbo.Users ADD CanViewReportProducts BIT NOT NULL CONSTRAINT DF_Users_CanViewReportProducts DEFAULT (0);

    IF COL_LENGTH(N'dbo.Users', N'CanViewReportEmployees') IS NULL
        ALTER TABLE dbo.Users ADD CanViewReportEmployees BIT NOT NULL CONSTRAINT DF_Users_CanViewReportEmployees DEFAULT (0);

    IF COL_LENGTH(N'dbo.Users', N'CanViewReportCashiers') IS NULL
        ALTER TABLE dbo.Users ADD CanViewReportCashiers BIT NOT NULL CONSTRAINT DF_Users_CanViewReportCashiers DEFAULT (0);

    IF COL_LENGTH(N'dbo.Users', N'CanViewReportCustomers') IS NULL
        ALTER TABLE dbo.Users ADD CanViewReportCustomers BIT NOT NULL CONSTRAINT DF_Users_CanViewReportCustomers DEFAULT (0);

    IF COL_LENGTH(N'dbo.Users', N'CanViewReportSuppliers') IS NULL
        ALTER TABLE dbo.Users ADD CanViewReportSuppliers BIT NOT NULL CONSTRAINT DF_Users_CanViewReportSuppliers DEFAULT (0);

    IF COL_LENGTH(N'dbo.Users', N'CanViewInventoryReport') IS NULL
        ALTER TABLE dbo.Users ADD CanViewInventoryReport BIT NOT NULL CONSTRAINT DF_Users_CanViewInventoryReport DEFAULT (0);
END;
GO

-- Tách batch để SQL Server biên dịch UPDATE sau khi các cột mới đã được tạo.
IF OBJECT_ID(N'dbo.Users', N'U') IS NOT NULL
   AND COL_LENGTH(N'dbo.Users', N'CanViewReports') IS NOT NULL
   AND COL_LENGTH(N'dbo.Users', N'CanViewReportOverview') IS NOT NULL
   AND COL_LENGTH(N'dbo.Users', N'CanViewReportCollections') IS NOT NULL
   AND COL_LENGTH(N'dbo.Users', N'CanViewReportRevenue') IS NOT NULL
   AND COL_LENGTH(N'dbo.Users', N'CanViewReportProducts') IS NOT NULL
   AND COL_LENGTH(N'dbo.Users', N'CanViewReportEmployees') IS NOT NULL
   AND COL_LENGTH(N'dbo.Users', N'CanViewReportCashiers') IS NOT NULL
   AND COL_LENGTH(N'dbo.Users', N'CanViewReportCustomers') IS NOT NULL
   AND COL_LENGTH(N'dbo.Users', N'CanViewReportSuppliers') IS NOT NULL
   AND COL_LENGTH(N'dbo.Users', N'CanViewInventoryReport') IS NOT NULL
BEGIN
    UPDATE dbo.Users
    SET CanViewReports = 1,
        CanViewReportOverview = 1,
        CanViewReportCollections = 1,
        CanViewReportRevenue = 1,
        CanViewReportProducts = 1,
        CanViewReportEmployees = 1,
        CanViewReportCashiers = 1,
        CanViewReportCustomers = 1,
        CanViewReportSuppliers = 1,
        CanViewInventoryReport = 1
    WHERE RoleId = 1 OR LOWER(ISNULL(Username, N'')) = N'admin';
END;
GO
