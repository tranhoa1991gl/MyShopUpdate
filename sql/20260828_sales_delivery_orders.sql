SET XACT_ABORT ON;
BEGIN TRANSACTION;

IF COL_LENGTH(N'dbo.orders', N'is_delivery') IS NULL
    ALTER TABLE dbo.orders ADD is_delivery BIT NOT NULL
        CONSTRAINT DF_orders_is_delivery DEFAULT (0) WITH VALUES;

IF COL_LENGTH(N'dbo.orders', N'delivery_recipient_name') IS NULL
    ALTER TABLE dbo.orders ADD delivery_recipient_name NVARCHAR(150) NULL;

IF COL_LENGTH(N'dbo.orders', N'delivery_phone') IS NULL
    ALTER TABLE dbo.orders ADD delivery_phone NVARCHAR(30) NULL;

IF COL_LENGTH(N'dbo.orders', N'delivery_address') IS NULL
    ALTER TABLE dbo.orders ADD delivery_address NVARCHAR(500) NULL;

IF COL_LENGTH(N'dbo.orders', N'delivery_status') IS NULL
    ALTER TABLE dbo.orders ADD delivery_status NVARCHAR(30) NULL;

COMMIT TRANSACTION;
