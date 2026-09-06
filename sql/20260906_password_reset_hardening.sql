/*
  20260906_password_reset_hardening.sql
  HoaTran POS - Password reset hardening

  Mục tiêu:
  - Thêm cờ MustChangePassword cho tài khoản được reset mật khẩu.
  - Mật khẩu tạm chỉ được lưu dưới dạng PBKDF2 hash bởi ứng dụng.
  - Người dùng phải đổi mật khẩu mới trước khi tiếp tục vào hệ thống.

  Script idempotent: có thể chạy lại nhiều lần.
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRANSACTION;

    IF OBJECT_ID(N'dbo.Users', N'U') IS NULL
        THROW 51330, N'Không tìm thấy bảng dbo.Users.', 1;

    IF COL_LENGTH(N'dbo.Users', N'MustChangePassword') IS NULL
    BEGIN
        ALTER TABLE dbo.Users
        ADD MustChangePassword BIT NOT NULL
            CONSTRAINT DF_Users_MustChangePassword DEFAULT (0) WITH VALUES;
    END
    ELSE
    BEGIN
        -- Dùng dynamic SQL để script vẫn compile an toàn nếu cột chưa tồn tại ở đầu batch.
        EXEC sys.sp_executesql N'
            UPDATE dbo.Users
            SET MustChangePassword = 0
            WHERE MustChangePassword IS NULL;
        ';

        IF EXISTS
        (
            SELECT 1
            FROM sys.columns
            WHERE object_id = OBJECT_ID(N'dbo.Users')
              AND name = N'MustChangePassword'
              AND is_nullable = 1
        )
        BEGIN
            EXEC sys.sp_executesql N'
                ALTER TABLE dbo.Users
                ALTER COLUMN MustChangePassword BIT NOT NULL;
            ';
        END;

        IF NOT EXISTS
        (
            SELECT 1
            FROM sys.default_constraints dc
            INNER JOIN sys.columns c
                ON c.object_id = dc.parent_object_id
               AND c.column_id = dc.parent_column_id
            WHERE dc.parent_object_id = OBJECT_ID(N'dbo.Users')
              AND c.name = N'MustChangePassword'
        )
        BEGIN
            ALTER TABLE dbo.Users
            ADD CONSTRAINT DF_Users_MustChangePassword
                DEFAULT (0) FOR MustChangePassword;
        END;
    END;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
