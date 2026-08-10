SET NOCOUNT ON;

IF OBJECT_ID(N'dbo.StoreInfo', N'U') IS NOT NULL
   AND COL_LENGTH(N'dbo.StoreInfo', N'remember_last_customer_price') IS NULL
BEGIN
    ALTER TABLE dbo.StoreInfo ADD remember_last_customer_price BIT NOT NULL
        CONSTRAINT DF_StoreInfo_remember_last_customer_price DEFAULT (0) WITH VALUES;
END;
