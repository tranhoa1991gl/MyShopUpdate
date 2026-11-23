-- Run against the selected HoaTranPOS database. The online updater may supply the transaction.
SET XACT_ABORT ON;
DECLARE @OwnTransaction bit = CASE WHEN @@TRANCOUNT = 0 THEN 1 ELSE 0 END;

BEGIN TRY
    IF @OwnTransaction = 1 BEGIN TRANSACTION;

    DECLARE @LockResult int;
    EXEC @LockResult = sys.sp_getapplock @Resource=N'POS.OperationsExtensions.Schema',
        @LockMode='Exclusive', @LockOwner='Transaction', @LockTimeout=15000;
    IF @LockResult < 0
        THROW 51000, N'Không thể khóa cập nhật cấu trúc khuyến mãi.', 1;

    IF OBJECT_ID(N'dbo.pos_ext_promotions', N'U') IS NULL
        THROW 51000, N'Cần khởi tạo Tiện ích cửa hàng trước khi cập nhật khuyến mãi.', 1;

    IF COL_LENGTH(N'dbo.pos_ext_promotions', N'promotion_type') IS NULL
        ALTER TABLE dbo.pos_ext_promotions ADD promotion_type nvarchar(30) NOT NULL
            CONSTRAINT DF_pos_ext_promotions_type DEFAULT N'DISCOUNT_PERCENT' WITH VALUES;
    IF COL_LENGTH(N'dbo.pos_ext_promotions', N'buy_quantity') IS NULL
        ALTER TABLE dbo.pos_ext_promotions ADD buy_quantity decimal(18,3) NOT NULL
            CONSTRAINT DF_pos_ext_promotions_buy_qty DEFAULT 1 WITH VALUES;
    IF COL_LENGTH(N'dbo.pos_ext_promotions', N'gift_quantity') IS NULL
        ALTER TABLE dbo.pos_ext_promotions ADD gift_quantity int NOT NULL
            CONSTRAINT DF_pos_ext_promotions_gift_qty DEFAULT 0 WITH VALUES;
    IF COL_LENGTH(N'dbo.pos_ext_promotions', N'gift_product_id') IS NULL
        ALTER TABLE dbo.pos_ext_promotions ADD gift_product_id int NULL;
    IF COL_LENGTH(N'dbo.pos_ext_promotions', N'is_multiply') IS NULL
        ALTER TABLE dbo.pos_ext_promotions ADD is_multiply bit NOT NULL
            CONSTRAINT DF_pos_ext_promotions_is_multiply DEFAULT 1 WITH VALUES;

    -- The original composite check has a generated name. Match its expression so other checks survive.
    DECLARE @DropLegacyChecks nvarchar(max) = N'';
    SELECT @DropLegacyChecks += N'ALTER TABLE dbo.pos_ext_promotions DROP CONSTRAINT ' + QUOTENAME(name) + N';'
    FROM sys.check_constraints
    WHERE parent_object_id = OBJECT_ID(N'dbo.pos_ext_promotions')
      AND LOWER(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(definition,
          N'[', N''), N']', N''), N'(', N''), N')', N''), N' ', N''), CHAR(13), N''), CHAR(10), N''))
          = N'ends_at>starts_atandminimum_quantity>0andminimum_total>=0anddiscount_percent>0anddiscount_percent<=100';
    IF @DropLegacyChecks <> N'' EXEC sys.sp_executesql @DropLegacyChecks;

    IF OBJECT_ID(N'dbo.CK_pos_ext_promotions_buy_x_get_y', N'C') IS NULL
        -- A same-product gift is already covered by the existing product_id foreign key.
        EXEC sys.sp_executesql N'
        ALTER TABLE dbo.pos_ext_promotions WITH CHECK ADD CONSTRAINT CK_pos_ext_promotions_buy_x_get_y CHECK
        (
            ends_at > starts_at AND minimum_quantity > 0 AND minimum_total >= 0 AND
            (
                (promotion_type = N''DISCOUNT_PERCENT'' AND discount_percent > 0 AND discount_percent <= 100)
                OR
                (promotion_type = N''BUY_X_GET_Y'' AND product_id IS NOT NULL AND product_id > 0
                    AND buy_quantity > 0 AND gift_quantity > 0 AND discount_percent = 0)
            )
            AND (gift_product_id IS NULL OR (product_id IS NOT NULL AND gift_product_id = product_id))
        );';

    IF @OwnTransaction = 1 COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @OwnTransaction = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
