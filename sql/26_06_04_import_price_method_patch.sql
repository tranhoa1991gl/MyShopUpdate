/*
    Migration: Chọn cách tính giá nhập
    1 = Bình quân gia quyền
    2 = Giá nhập mới nhất
*/

IF COL_LENGTH('dbo.StoreInfo', 'import_price_method') IS NULL
BEGIN
    ALTER TABLE dbo.StoreInfo
    ADD import_price_method INT NOT NULL
        CONSTRAINT DF_StoreInfo_import_price_method DEFAULT (1);
END
GO

UPDATE dbo.StoreInfo
SET import_price_method = 1
WHERE import_price_method IS NULL
   OR import_price_method NOT IN (1, 2);
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.check_constraints
    WHERE name = N'CK_StoreInfo_import_price_method'
      AND parent_object_id = OBJECT_ID(N'dbo.StoreInfo')
)
BEGIN
    ALTER TABLE dbo.StoreInfo
    ADD CONSTRAINT CK_StoreInfo_import_price_method
    CHECK (import_price_method IN (1, 2));
END
GO

CREATE OR ALTER PROCEDURE [dbo].[StoreInfo_Get]
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP 1 
        store_name AS StoreName,
        address AS Address,
        phone AS Phone,
        email AS Email,
        wifi_pass AS WifiPass,
        tax_code AS TaxCode,
        bank_name AS BankName,
        bank_account AS BankAccount,
        bank_owner AS BankOwner,
        points_earn_rate AS PointsEarnRate,
        points_use_rate AS PointsUseRate,
        ISNULL(import_price_method, 1) AS ImportPriceMethod
    FROM dbo.StoreInfo;
END
GO

CREATE OR ALTER PROCEDURE [dbo].[StoreInfo_Save]
    @StoreName NVARCHAR(255),
    @Address NVARCHAR(500),
    @Phone VARCHAR(20),
    @Email VARCHAR(100),
    @WifiPass VARCHAR(50),
    @TaxCode VARCHAR(50),
    @BankName NVARCHAR(50),
    @BankAccount VARCHAR(50),
    @BankOwner NVARCHAR(100),
    @PointsEarnRate DECIMAL(18,0) = 100000,
    @PointsUseRate DECIMAL(18,0) = 1000,
    @ImportPriceMethod INT = 1
AS
BEGIN
    SET NOCOUNT ON;

    IF ISNULL(@ImportPriceMethod, 1) NOT IN (1, 2)
        SET @ImportPriceMethod = 1;

    IF EXISTS (SELECT 1 FROM dbo.StoreInfo)
    BEGIN
        UPDATE dbo.StoreInfo
        SET store_name = @StoreName,
            address = @Address,
            phone = @Phone,
            email = @Email,
            wifi_pass = @WifiPass,
            tax_code = @TaxCode,
            bank_name = @BankName,
            bank_account = @BankAccount,
            bank_owner = @BankOwner,
            points_earn_rate = @PointsEarnRate,
            points_use_rate = @PointsUseRate,
            import_price_method = @ImportPriceMethod;
    END
    ELSE
    BEGIN
        INSERT INTO dbo.StoreInfo
        (
            store_name,
            address,
            phone,
            email,
            wifi_pass,
            tax_code,
            bank_name,
            bank_account,
            bank_owner,
            points_earn_rate,
            points_use_rate,
            import_price_method
        )
        VALUES
        (
            @StoreName,
            @Address,
            @Phone,
            @Email,
            @WifiPass,
            @TaxCode,
            @BankName,
            @BankAccount,
            @BankOwner,
            @PointsEarnRate,
            @PointsUseRate,
            @ImportPriceMethod
        );
    END
END
GO

CREATE OR ALTER PROCEDURE [dbo].[Product_IncreaseStock]
    @ProductId INT,
    @Quantity INT,
    @NewImportPrice DECIMAL(18,0)
AS
BEGIN
    SET NOCOUNT ON;

    IF ISNULL(@Quantity, 0) <= 0
        RETURN;

    -- Hàng bảo hành / đổi trả giá 0: chỉ cộng tồn, không đổi giá nhập.
    IF ISNULL(@NewImportPrice, 0) <= 0
    BEGIN
        UPDATE dbo.products
        SET stock = ISNULL(stock, 0) + @Quantity
        WHERE product_id = @ProductId;

        RETURN;
    END

    DECLARE @ImportPriceMethod INT = 1;

    SELECT TOP 1
        @ImportPriceMethod = ISNULL(import_price_method, 1)
    FROM dbo.StoreInfo;

    IF @ImportPriceMethod NOT IN (1, 2)
        SET @ImportPriceMethod = 1;

    UPDATE dbo.products
    SET import_price = CASE
            -- 2 = giá nhập mới nhất
            WHEN @ImportPriceMethod = 2 THEN @NewImportPrice

            -- 1 = bình quân gia quyền
            WHEN ISNULL(stock, 0) <= 0 THEN @NewImportPrice
            ELSE ((ISNULL(stock, 0) * ISNULL(import_price, 0)) + (@Quantity * @NewImportPrice))
                 / NULLIF(ISNULL(stock, 0) + @Quantity, 0)
        END,
        stock = ISNULL(stock, 0) + @Quantity
    WHERE product_id = @ProductId;
END
GO