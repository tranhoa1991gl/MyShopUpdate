/*
  20260906_login_lockout_hardening.sql
  HoaTran POS - Login security hardening

  Mục tiêu:
  - Theo dõi số lần đăng nhập sai theo tài khoản trên SQL Server dùng chung.
  - Sau 5 lần sai liên tiếp: khóa tạm 1 phút (logic thực thi ở ứng dụng).
  - Đăng nhập đúng: ứng dụng reset bộ đếm về 0.

  Script idempotent: có thể chạy lại nhiều lần.
  Lưu ý: dùng dynamic SQL cho các câu lệnh tham chiếu cột mới để tránh
  lỗi compile-time "Invalid column name" trong cùng batch SQL Server.
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRANSACTION;

    IF OBJECT_ID(N'dbo.Users', N'U') IS NULL
        THROW 51320, N'Không tìm thấy bảng dbo.Users.', 1;

    IF COL_LENGTH(N'dbo.Users', N'FailedLoginCount') IS NULL
    BEGIN
        ALTER TABLE dbo.Users
        ADD FailedLoginCount INT NOT NULL
            CONSTRAINT DF_Users_FailedLoginCount DEFAULT (0);
    END;

    IF COL_LENGTH(N'dbo.Users', N'LockedUntil') IS NULL
    BEGIN
        ALTER TABLE dbo.Users
        ADD LockedUntil DATETIME2(0) NULL;
    END;

    -- Dùng dynamic SQL vì cột có thể vừa được ADD trong chính batch này.
    EXEC sys.sp_executesql N'
        UPDATE dbo.Users
        SET FailedLoginCount = 0
        WHERE FailedLoginCount < 0;
    ';

    IF NOT EXISTS
    (
        SELECT 1
        FROM sys.check_constraints
        WHERE parent_object_id = OBJECT_ID(N'dbo.Users')
          AND name = N'CK_Users_FailedLoginCount_NonNegative'
    )
    BEGIN
        EXEC sys.sp_executesql N'
            ALTER TABLE dbo.Users WITH CHECK
            ADD CONSTRAINT CK_Users_FailedLoginCount_NonNegative
                CHECK (FailedLoginCount >= 0);
        ';

        ALTER TABLE dbo.Users
        CHECK CONSTRAINT CK_Users_FailedLoginCount_NonNegative;
    END;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
