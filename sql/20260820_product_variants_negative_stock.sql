SET XACT_ABORT ON;
BEGIN TRANSACTION;

/*
   Cho phép giữ nguyên tồn kho âm của từng biến thể khi import từ KiotViet.
   Không sửa dữ liệu hiện có; chỉ bỏ CHECK constraint từng ép stock_base_qty >= 0.
*/
IF OBJECT_ID(N'dbo.product_variants', N'U') IS NOT NULL
BEGIN
    DECLARE @DropNegativeStockConstraintSql NVARCHAR(MAX) = N'';
    SELECT @DropNegativeStockConstraintSql = @DropNegativeStockConstraintSql
        + N'ALTER TABLE dbo.product_variants DROP CONSTRAINT ' + QUOTENAME(name) + N';'
    FROM sys.check_constraints
    WHERE parent_object_id = OBJECT_ID(N'dbo.product_variants')
      AND definition LIKE N'%stock_base_qty%';

    IF LEN(@DropNegativeStockConstraintSql) > 0
        EXEC sys.sp_executesql @DropNegativeStockConstraintSql;
END;

COMMIT TRANSACTION;
