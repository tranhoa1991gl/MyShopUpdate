IF OBJECT_ID(N'dbo.__TestOnlineUpdate', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.__TestOnlineUpdate
    (
        Id INT IDENTITY(1,1) PRIMARY KEY,
        Note NVARCHAR(200) NULL,
        CreatedAt DATETIME NOT NULL DEFAULT GETDATE()
    )
END
GO

IF NOT EXISTS (
    SELECT 1
    FROM dbo.__TestOnlineUpdate
    WHERE Note = N'Test update SQL online'
)
BEGIN
    INSERT INTO dbo.__TestOnlineUpdate(Note)
    VALUES (N'Test update SQL online')
END
GO
