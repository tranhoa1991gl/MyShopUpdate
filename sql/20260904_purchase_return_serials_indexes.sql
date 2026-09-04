SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRANSACTION;

    IF OBJECT_ID(N'dbo.purchase_return_serials', N'U') IS NULL
    BEGIN
        CREATE TABLE dbo.purchase_return_serials
        (
            return_serial_id INT IDENTITY(1,1) NOT NULL
                CONSTRAINT PK_purchase_return_serials PRIMARY KEY,
            return_id INT NOT NULL,
            return_detail_id INT NOT NULL,
            serial_id INT NOT NULL,
            serial_number NVARCHAR(100) NOT NULL,
            created_at DATETIME NOT NULL
                CONSTRAINT DF_purchase_return_serials_created DEFAULT (GETDATE())
        );
    END;

    IF NOT EXISTS
    (
        SELECT 1
        FROM sys.indexes
        WHERE object_id = OBJECT_ID(N'dbo.purchase_return_serials')
          AND name = N'IX_purchase_return_serials_return'
    )
        CREATE INDEX IX_purchase_return_serials_return
            ON dbo.purchase_return_serials(return_id);

    IF NOT EXISTS
    (
        SELECT 1
        FROM sys.indexes
        WHERE object_id = OBJECT_ID(N'dbo.purchase_return_serials')
          AND name = N'IX_purchase_return_serials_detail'
    )
        CREATE INDEX IX_purchase_return_serials_detail
            ON dbo.purchase_return_serials(return_detail_id);

    IF NOT EXISTS
    (
        SELECT 1
        FROM sys.indexes
        WHERE object_id = OBJECT_ID(N'dbo.purchase_return_serials')
          AND name = N'IX_purchase_return_serials_serial'
    )
        CREATE INDEX IX_purchase_return_serials_serial
            ON dbo.purchase_return_serials(serial_id);

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;
    THROW;
END CATCH;
