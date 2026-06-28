IF COL_LENGTH(N'dbo.order_items', N'stock_before') IS NULL
BEGIN
    ALTER TABLE dbo.order_items ADD stock_before INT NULL;
END
GO

IF COL_LENGTH(N'dbo.order_items', N'stock_after') IS NULL
BEGIN
    ALTER TABLE dbo.order_items ADD stock_after INT NULL;
END
GO
