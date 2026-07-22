IF COL_LENGTH(N'dbo.order_items', N'gift_quantity') IS NULL
BEGIN
    ALTER TABLE dbo.order_items
    ADD gift_quantity INT NOT NULL
        CONSTRAINT DF_order_items_gift_quantity DEFAULT(0) WITH VALUES;
END
GO
