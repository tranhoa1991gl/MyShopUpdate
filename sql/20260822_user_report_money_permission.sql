SET XACT_ABORT ON;

/*
   Cho phép cấp riêng quyền xem các số tiền trong màn hình Báo cáo.
   Dùng migration mới vì migration phân quyền báo cáo trước có thể đã được ghi nhận là đã chạy.
*/

IF OBJECT_ID(N'dbo.Users', N'U') IS NOT NULL
   AND COL_LENGTH(N'dbo.Users', N'CanViewReportMoney') IS NULL
BEGIN
    ALTER TABLE dbo.Users
    ADD CanViewReportMoney BIT NOT NULL
        CONSTRAINT DF_Users_CanViewReportMoney DEFAULT (0);
END;
GO

IF OBJECT_ID(N'dbo.Users', N'U') IS NOT NULL
   AND COL_LENGTH(N'dbo.Users', N'CanViewReportMoney') IS NOT NULL
BEGIN
    EXEC(N'
        UPDATE dbo.Users
        SET CanViewReportMoney = 1
        WHERE RoleId = 1 OR LOWER(ISNULL(Username, N'''')) = N''admin'';
    ');
END;
GO
