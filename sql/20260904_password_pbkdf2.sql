USE [DBMyShop]
GO
SET NOCOUNT ON;
GO

/* Fix 13 - Chuẩn bị cột mật khẩu cho PBKDF2.
   Không đổi mật khẩu hiện tại bằng SQL.
   Tài khoản MD5 cũ sẽ tự nâng cấp sau lần đăng nhập thành công đầu tiên. */

IF COL_LENGTH(N'dbo.Users', N'PasswordHash') IS NOT NULL
BEGIN
    UPDATE dbo.Users
    SET PasswordHash = N''
    WHERE PasswordHash IS NULL;

    IF COL_LENGTH(N'dbo.Users', N'PasswordHash') < 510
        ALTER TABLE dbo.Users
        ALTER COLUMN PasswordHash NVARCHAR(255) NOT NULL;
END
GO

IF OBJECT_ID(N'dbo.Users_ResetPassword', N'P') IS NOT NULL
BEGIN
    EXEC(N'
ALTER PROCEDURE [dbo].[Users_ResetPassword]
    @UserId INT,
    @PasswordHash NVARCHAR(255)
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dbo.Users
    SET PasswordHash = @PasswordHash
    WHERE UserId = @UserId;
END');
END
GO
