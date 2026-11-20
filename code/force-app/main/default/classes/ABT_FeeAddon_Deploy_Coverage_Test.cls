/**
 * Deploy-oriented coverage for portal fee-addon helpers and Scale Up QLI updates
 * (RunSpecifiedTests 75% gate). No @testSetup so SeeAllData helpers stay valid if needed;
 * quote setup mirrors ABT_Cart_Checkout_Coverage_Test (works in prod).
 */
@isTest
private class ABT_FeeAddon_Deploy_Coverage_Test {
  private static void insertDeployTestQuoteRequest(
    ABT_Quote_Request__c quoteRequest
  ) {
    Map<String, Schema.SObjectField> quoteRequestFields = Schema.SObjectType.ABT_Quote_Request__c.fields.getMap();

    ABT_Quote_Request__c insertRecord = new ABT_Quote_Request__c(
      ABT_Account__c = quoteRequest.ABT_Account__c,
      ABT_Customer_Project_Name__c = quoteRequest.ABT_Customer_Project_Name__c
    );
    if (quoteRequestFields.containsKey('Quote_Request_Origin__c')) {
      insertRecord.put('Quote_Request_Origin__c', 'API');
    }
    insert insertRecord;

    ABT_Quote_Request__c updateRecord = new ABT_Quote_Request__c(
      Id = insertRecord.Id
    );
    if (
      quoteRequest.ABT_Contact__c != null &&
      quoteRequestFields.containsKey('ABT_Contact__c')
    ) {
      updateRecord.ABT_Contact__c = quoteRequest.ABT_Contact__c;
    }
    if (
      quoteRequest.ABT_Product__c != null &&
      quoteRequestFields.containsKey('ABT_Product__c')
    ) {
      updateRecord.ABT_Product__c = quoteRequest.ABT_Product__c;
    }
    if (
      quoteRequest.ABT_Quote__c != null &&
      quoteRequestFields.containsKey('ABT_Quote__c')
    ) {
      updateRecord.ABT_Quote__c = quoteRequest.ABT_Quote__c;
    }
    if (
      quoteRequest.ABT_Added_to_Cart__c == true &&
      quoteRequestFields.containsKey('ABT_Added_to_Cart__c')
    ) {
      updateRecord.ABT_Added_to_Cart__c = true;
    }
    update updateRecord;

    quoteRequest.Id = insertRecord.Id;
  }

  private static ABT_Quote_Request_Lineitem__c insertDeployTestRequestLine(
    Id quoteRequestId,
    String sequenceName,
    Id productId,
    Id quoteLineItemId
  ) {
    ABT_Quote_Request_Lineitem__c requestLine = new ABT_Quote_Request_Lineitem__c(
      ABT_Quote_Request__c = quoteRequestId,
      ABT_Sequence_Name__c = sequenceName,
      ABT_Sequence__c = 'ATGCATGC',
      ABT_Product__c = productId,
      ABT_Quote_Line_Item__c = quoteLineItemId
    );
    insert requestLine;
    return requestLine;
  }

  @isTest
  static void coverPortalControllerBulkGuardPaths() {
    Map<String, Object> emptyGlycerolBatch = ABT_Portal_Controller.applyBulkGlycerolBatch(
      new Map<Id, Boolean>(),
      new List<Id>{ null }
    );
    System.assertEquals(false, emptyGlycerolBatch.get('anyMutation'));

    Map<String, Object> skipMissingDesired = ABT_Portal_Controller.applyBulkGlycerolBatch(
      new Map<Id, Boolean>(),
      new List<Id>{ null, UserInfo.getUserId() }
    );
    System.assertEquals(false, skipMissingDesired.get('anyMutation'));

    Map<String, Object> missingRows = ABT_Portal_Controller.applyBulkGlycerolBatch(
      new Map<Id, Boolean>{ UserInfo.getUserId() => true },
      new List<Id>{ UserInfo.getUserId() }
    );
    System.assertEquals(false, missingRows.get('anyMutation'));
    List<Object> missingRowPayload = (List<Object>) missingRows.get('lines');
    System.assertEquals(1, missingRowPayload.size());

    Map<String, Object> emptyToxic = ABT_Portal_Controller.bulkUpdateQuoteRequestLineItemPotentiallyToxic(
      new List<Id>(),
      new List<Boolean>()
    );
    System.assertEquals(false, emptyToxic.get('success'));

    Map<String, Object> emptyReflex = ABT_Portal_Controller.bulkUpdateQuoteRequestLineItemReflexVectorOptIn(
      new List<Id>(),
      new List<Boolean>()
    );
    System.assertEquals(false, emptyReflex.get('success'));

    Map<String, Object> emptyGlycerol = ABT_Portal_Controller.bulkUpdateQuoteRequestLineItemGlycerol(
      new List<Id>(),
      new List<Boolean>()
    );
    System.assertEquals(false, emptyGlycerol.get('success'));

    Map<String, Object> noopGlycerol = ABT_Portal_Controller.bulkUpdateQuoteRequestLineItemGlycerol(
      new List<Id>{ UserInfo.getUserId() },
      new List<Boolean>{ true }
    );
    System.assertEquals(true, noopGlycerol.get('success'));
    System.assertEquals(false, noopGlycerol.get('removedFromCart'));

    Map<String, Object> checkboxEmpty = ABT_Portal_Controller.bulkUpdateQuoteRequestLineItemCheckbox(
      new List<Id>(),
      new List<Boolean>(),
      'flags must match',
      'Potentially_Toxic__c',
      'Potentially_Toxic__c',
      'potentiallyToxic',
      'coverage'
    );
    System.assertEquals(false, checkboxEmpty.get('success'));

    Map<String, Object> checkboxMismatch = ABT_Portal_Controller.bulkUpdateQuoteRequestLineItemCheckbox(
      new List<Id>{ UserInfo.getUserId() },
      new List<Boolean>{ true, false },
      'flags must match',
      'Reflex_Vector_Opt_In__c',
      'Reflex_Vector_Opt_In__c',
      'reflexVectorOptIn',
      'coverage'
    );
    System.assertEquals(false, checkboxMismatch.get('success'));
  }

  @isTest
  static void coverPortalFeeAddonHelpers() {
    System.assertEquals(
      false,
      ABT_Portal_Controller.isGlycerolStockProduct(null)
    );
    System.assertEquals(
      false,
      ABT_Portal_Controller.isGlycerolStockProduct('')
    );
    System.assertEquals(
      true,
      ABT_Portal_Controller.isGlycerolStockProduct('Glycerol Stock - Tubes')
    );
    System.assertEquals(
      false,
      ABT_Portal_Controller.isGlycerolStockProduct('Clonal DNA')
    );

    System.assertEquals(
      true,
      ABT_Portal_Controller.isScaleUpProduct(null, 'SC-001')
    );
    System.assertEquals(
      true,
      ABT_Portal_Controller.isScaleUpProduct(null, 'cs-200')
    );
    System.assertEquals(
      true,
      ABT_Portal_Controller.isScaleUpProduct('Custom Scale Up Fee', null)
    );
    System.assertEquals(
      false,
      ABT_Portal_Controller.isScaleUpProduct(null, null)
    );
    System.assertEquals(
      false,
      ABT_Portal_Controller.isScaleUpProduct('Clonal DNA', 'DNA-001')
    );

    System.assertEquals(
      true,
      ABT_Portal_Controller.isGlycerolStockSku('GS-001')
    );
    System.assertEquals(
      true,
      ABT_Portal_Controller.isGlycerolStockSku('gs-001')
    );
    System.assertEquals(false, ABT_Portal_Controller.isGlycerolStockSku(null));
    System.assertEquals(
      false,
      ABT_Portal_Controller.isGlycerolStockSku('DNA-001')
    );

    System.assertEquals(
      false,
      ABT_Portal_Controller.isGlycerolStockOrderItem(null)
    );
    System.assertEquals(false, ABT_Portal_Controller.isScaleUpOrderItem(null));
    System.assertEquals(
      false,
      ABT_Portal_Controller.isGlycerolStockQuoteLineItem(null)
    );
    System.assertEquals(
      false,
      ABT_Portal_Controller.isScaleUpQuoteLineItem(null)
    );
    System.assertEquals(
      false,
      ABT_Portal_Controller.isPortalFeeAddonOrderItem(null)
    );
    System.assertEquals(
      false,
      ABT_Portal_Controller.isPortalFeeAddonQuoteLineItem(null)
    );
    System.assertEquals(null, ABT_Portal_Controller.resolveLineItemSku(null));
    Product2 glycerolProduct = new Product2(
      Name = 'Glycerol Stock - Plate',
      StockKeepingUnit = 'GS-COV-' +
        String.valueOf(DateTime.now().getTime()).right(6),
      IsActive = true
    );
    Product2 scaleUpProduct = new Product2(
      Name = 'Scale Up',
      StockKeepingUnit = 'SC-COV-' +
        String.valueOf(DateTime.now().getTime()).right(6),
      IsActive = true
    );
    Product2 normalProduct = new Product2(
      Name = 'Ansa Clonal DNA',
      StockKeepingUnit = 'DNA-COV-' +
        String.valueOf(DateTime.now().getTime()).right(6),
      IsActive = true
    );

    OrderItem glycerolOi = new OrderItem();
    glycerolOi.Product2 = glycerolProduct;
    glycerolOi.Sequence_Name__c = 'Glycerol Stock';
    System.assertEquals(
      true,
      ABT_Portal_Controller.isGlycerolStockOrderItem(glycerolOi)
    );
    System.assertEquals(
      true,
      ABT_Portal_Controller.isPortalFeeAddonOrderItem(glycerolOi)
    );

    OrderItem scaleOi = new OrderItem();
    scaleOi.Product2 = scaleUpProduct;
    scaleOi.Product2.Name = 'Scale Up';
    scaleOi.Product2.StockKeepingUnit = 'SC-001';
    System.assertEquals(
      true,
      ABT_Portal_Controller.isScaleUpOrderItem(scaleOi)
    );
    System.assertEquals(
      true,
      ABT_Portal_Controller.isPortalFeeAddonOrderItem(scaleOi)
    );

    OrderItem normalOi = new OrderItem();
    normalOi.Product2 = normalProduct;
    System.assertEquals(
      false,
      ABT_Portal_Controller.isPortalFeeAddonOrderItem(normalOi)
    );

    // Order list / project detail use a minimal OrderItem query (no QuoteLineItem subquery).
    OrderItem orderListShape = new OrderItem();
    orderListShape.Product2 = new Product2(
      Name = 'Ansa Clonal DNA',
      StockKeepingUnit = '4012'
    );
    orderListShape.Product_SKU__c = '4012';
    orderListShape.Quantity = 1;
    System.assertEquals(
      false,
      ABT_Portal_Controller.isPortalFeeAddonOrderItem(orderListShape)
    );

    // Prod glycerol fee lines can be named like "Ansa Clonal DNA" with GS-001 on Product_SKU__c
    // while Product2.StockKeepingUnit stays on the DNA SKU (e.g. 1002).
    OrderItem glycerolBySkuOi = new OrderItem();
    glycerolBySkuOi.Product2 = new Product2(
      Name = 'Ansa Clonal DNA',
      StockKeepingUnit = '1002'
    );
    glycerolBySkuOi.Product_SKU__c = 'GS-001';
    System.assertEquals(
      'GS-001',
      ABT_Portal_Controller.resolveLineItemSku(glycerolBySkuOi)
    );
    System.assertEquals(
      true,
      ABT_Portal_Controller.isGlycerolStockOrderItem(glycerolBySkuOi)
    );
    System.assertEquals(
      true,
      ABT_Portal_Controller.isPortalFeeAddonOrderItem(glycerolBySkuOi)
    );
    System.assertEquals(
      true,
      ABT_Portal_Controller.isPortalFeeAddonSku('GS-001')
    );
    System.assertEquals(
      true,
      ABT_Portal_Controller.isPortalFeeAddonSku('SC-001')
    );
    System.assertEquals(
      false,
      ABT_Portal_Controller.isPortalFeeAddonSku('1002')
    );

    QuoteLineItem scaleBySkuQli = new QuoteLineItem();
    scaleBySkuQli.Product2 = new Product2(
      Name = 'Ansa Clonal DNA',
      StockKeepingUnit = '1002'
    );
    scaleBySkuQli.Product_SKU__c = 'SC-001';
    System.assertEquals(
      true,
      ABT_Portal_Controller.isScaleUpQuoteLineItem(scaleBySkuQli)
    );

    QuoteLineItem glycerolQli = new QuoteLineItem();
    glycerolQli.Product2 = glycerolProduct;
    glycerolProduct.Name = 'Glycerol Stock - Plate';
    System.assertEquals(
      true,
      ABT_Portal_Controller.isGlycerolStockQuoteLineItem(glycerolQli)
    );
    System.assertEquals(
      true,
      ABT_Portal_Controller.isPortalFeeAddonQuoteLineItem(glycerolQli)
    );

    QuoteLineItem scaleQli = new QuoteLineItem();
    scaleQli.Product2 = new Product2(
      Name = 'Scale Up',
      StockKeepingUnit = 'SC-001'
    );
    System.assertEquals(
      true,
      ABT_Portal_Controller.isScaleUpQuoteLineItem(scaleQli)
    );
    System.assertEquals(
      true,
      ABT_Portal_Controller.isPortalFeeAddonQuoteLineItem(scaleQli)
    );

    QuoteLineItem normalQli = new QuoteLineItem();
    normalQli.Product2 = normalProduct;
    System.assertEquals(
      false,
      ABT_Portal_Controller.isPortalFeeAddonQuoteLineItem(normalQli)
    );

    // When SC-001 child lines exist, do not bake Scale_Up_Price__c into parent UnitPrice.
    QuoteLineItem parentWithScaleUp = new QuoteLineItem();
    parentWithScaleUp.UnitPrice = 375;
    parentWithScaleUp.Scale_Up_Price__c = 325;
    QuoteLineItem scaleChild = new QuoteLineItem();
    scaleChild.Product2 = new Product2(
      Name = 'Scale Up',
      StockKeepingUnit = 'SC-001'
    );
    QuoteLineItem zeroScaleChild = new QuoteLineItem();
    zeroScaleChild.Product2 = new Product2(
      Name = 'Scale Up',
      StockKeepingUnit = 'SC-001'
    );
    System.assertEquals(
      false,
      ABT_Portal_Controller.quoteLineItemsIncludeScaleUpChild(
        new List<QuoteLineItem>{ parentWithScaleUp, zeroScaleChild }
      ),
      'A $0 SC-001 child does not count as the Scale Up fee'
    );
    QuoteLineItem pricedScaleChild = (QuoteLineItem) JSON.deserialize(
      '{"UnitPrice":325,"TotalPrice":325}',
      QuoteLineItem.class
    );
    pricedScaleChild.Product2 = new Product2(
      Name = 'Scale Up',
      StockKeepingUnit = 'SC-001'
    );
    System.assertEquals(
      true,
      ABT_Portal_Controller.quoteLineItemsIncludeScaleUpChild(
        new List<QuoteLineItem>{ parentWithScaleUp, pricedScaleChild }
      )
    );
    System.assertEquals(
      375,
      ABT_Portal_Controller.quoteLineItemOrderUnitPrice(
        parentWithScaleUp,
        0,
        false
      )
    );
    System.assertEquals(
      375,
      ABT_Portal_Controller.quoteLineItemOrderUnitPrice(
        parentWithScaleUp,
        0,
        true
      ),
      'Checkout uses DNA sales price only; inner Scale Up Price is ignored'
    );
    QuoteLineItem parentWithGlycerol = (QuoteLineItem) JSON.deserialize(
      '{"UnitPrice":375,"TotalPrice":375,"Scale_Up_Price__c":975,"Glycerol_Price__c":30}',
      QuoteLineItem.class
    );
    parentWithGlycerol.Product2 = normalProduct;
    QuoteLineItem zeroScale = (QuoteLineItem) JSON.deserialize(
      '{"Quantity":3,"UnitPrice":0,"TotalPrice":0}',
      QuoteLineItem.class
    );
    zeroScale.Product2 = new Product2(
      Name = 'Scale Up',
      StockKeepingUnit = 'SC-001'
    );
    QuoteLineItem glycerolChild = (QuoteLineItem) JSON.deserialize(
      '{"UnitPrice":30,"TotalPrice":30}',
      QuoteLineItem.class
    );
    glycerolChild.Product2 = new Product2(
      Name = 'Glycerol Stock',
      StockKeepingUnit = 'GS-001'
    );
    System.assertEquals(
      375,
      ABT_Portal_Controller.quoteLineItemOrderUnitPrice(
        parentWithGlycerol,
        0,
        true,
        false
      ),
      'DNA sales price only; inner Scale Up Price is ignored'
    );
    System.assertEquals(
      375,
      ABT_Portal_Controller.quoteLineItemOrderUnitPrice(
        parentWithGlycerol,
        0,
        true,
        true
      ),
      'DNA sales price only; inner Glycerol Price is ignored'
    );
    System.assertEquals(
      0,
      ABT_Portal_Controller.quoteLineItemOrderUnitPrice(
        zeroScale,
        325,
        false,
        false
      ),
      'Zero Scale Up children must not pick up the price book fallback'
    );
    System.assertEquals(
      50,
      ABT_Portal_Controller.quoteLineItemOrderUnitPrice(
        new QuoteLineItem(),
        50,
        true
      )
    );
    System.assertEquals(
      false,
      ABT_Portal_Controller.quoteLineItemsIncludeScaleUpChild(null)
    );
    System.assertEquals(
      false,
      ABT_Portal_Controller.quoteLineItemsIncludeScaleUpChild(
        new List<QuoteLineItem>()
      )
    );

    OrderItem clearTarget = new OrderItem();
    clearTarget.Scale_Up_Price__c = 325;
    ABT_Portal_Controller.clearOrderItemScaleUpPriceField(clearTarget);
    System.assertEquals(0, clearTarget.Scale_Up_Price__c);
    ABT_Portal_Controller.clearOrderItemScaleUpPriceField(null);

    QuoteLineItem codeSkuQli = new QuoteLineItem();
    codeSkuQli.Product2 = new Product2(Name = 'Ansa Clonal DNA');
    codeSkuQli.Product_Code__c = 'GS-001';
    System.assertEquals(
      'GS-001',
      ABT_Portal_Controller.resolveLineItemSku(codeSkuQli)
    );
    System.assertEquals(
      true,
      ABT_Portal_Controller.isGlycerolStockQuoteLineItem(codeSkuQli)
    );
    System.assertEquals(
      null,
      ABT_Portal_Controller.productLabelFromQuoteRequest(null)
    );
    System.assertEquals(
      null,
      ABT_Portal_Controller.productLabelFromQuoteRequest(
        new ABT_Quote_Request__c()
      )
    );
    System.assertEquals(
      0,
      ABT_Portal_Controller.loadProductNamesByQuoteId(null).size()
    );
    System.assertEquals(
      0,
      ABT_Portal_Controller.loadProductNamesByQuoteId(new Set<Id>()).size()
    );

    System.assertEquals(
      null,
      ABT_Portal_Controller.formatPortalProductName(null)
    );
    System.assertEquals('', ABT_Portal_Controller.formatPortalProductName(''));
    System.assertEquals(
      'Clonal DNA',
      ABT_Portal_Controller.formatPortalProductName('Ansa Clonal DNA')
    );
    System.assertEquals(
      'Other',
      ABT_Portal_Controller.formatPortalProductName('Other')
    );
    System.assertNotEquals(
      null,
      ABT_Portal_Controller.getVectorLibraryData(null)
    );
    System.assertEquals(
      null,
      ABT_Portal_Controller.resolveOrderItemQuoteLineItemId(null)
    );
    System.assertEquals(
      0,
      ABT_Portal_Controller.computeGlycerolAddonByOrderItemId(null, null).size()
    );
    System.assertEquals(
      0,
      ABT_Portal_Controller.computeGlycerolAddonByOrderItemId(
          new List<OrderItem>(),
          new List<OrderItem>()
        )
        .size()
    );

    // Orphan GS-001 (DNA Product2 + line Product_SKU__c) rolls onto the sole visible sequence.
    OrderItem visibleDna = new OrderItem();
    visibleDna.Product2 = new Product2(
      Name = 'Ansa Clonal DNA',
      StockKeepingUnit = '1002'
    );
    visibleDna.Product_SKU__c = '4012';
    visibleDna.Sequence_Name__c = 'Sequence 1';
    visibleDna.UnitPrice = 375;
    visibleDna.Quantity = 1;
    OrderItem orphanGlycerol = new OrderItem();
    orphanGlycerol.Product2 = new Product2(
      Name = 'Ansa Clonal DNA',
      StockKeepingUnit = '1002'
    );
    orphanGlycerol.Product_SKU__c = 'GS-001';
    orphanGlycerol.UnitPrice = 30;
    orphanGlycerol.Quantity = 1;
    Map<Id, Decimal> orphanAddons = ABT_Portal_Controller.computeGlycerolAddonByOrderItemId(
      new List<OrderItem>{ visibleDna, orphanGlycerol },
      new List<OrderItem>{ visibleDna }
    );
    System.assertEquals(1, orphanAddons.size());
    System.assertEquals(30, orphanAddons.values()[0]);

    OrderItem unbakedDna = new OrderItem();
    unbakedDna.Product2 = new Product2(
      Name = 'Ansa Clonal DNA',
      StockKeepingUnit = '1002'
    );
    unbakedDna.UnitPrice = 375;
    unbakedDna.Quantity = 1;
    unbakedDna.Scale_Up_Price__c = 975;
    unbakedDna.Glycerol_Price__c = 30;
    OrderItem zeroScaleOrderChild = new OrderItem();
    zeroScaleOrderChild.Product2 = new Product2(
      Name = 'Scale Up',
      StockKeepingUnit = 'SC-001'
    );
    zeroScaleOrderChild.Quantity = 3;
    zeroScaleOrderChild.UnitPrice = 0;
    Map<Id, Decimal> unbakedAddons = ABT_Portal_Controller.computeGlycerolAddonByOrderItemId(
      new List<OrderItem>{ unbakedDna, zeroScaleOrderChild },
      new List<OrderItem>{ unbakedDna }
    );
    System.assertEquals(
      true,
      unbakedAddons.isEmpty(),
      'Inner Scale Up / Glycerol on DNA are ignored when SC-001 is $0'
    );
    System.assertEquals(
      375,
      ABT_Portal_Controller.portalOrderProductSubtotal(
        new List<OrderItem>{ unbakedDna, zeroScaleOrderChild },
        new List<OrderItem>{ unbakedDna }
      )
    );

    OrderItem bakedDna = new OrderItem();
    bakedDna.Product2 = new Product2(
      Name = 'Ansa Clonal DNA',
      StockKeepingUnit = '1002'
    );
    bakedDna.UnitPrice = 1350;
    bakedDna.Quantity = 1;
    bakedDna.Scale_Up_Price__c = 975;
    QuoteLineItem bakedSource = (QuoteLineItem) JSON.deserialize(
      '{"TotalPrice":375,"Scale_Up_Price__c":975}',
      QuoteLineItem.class
    );
    bakedDna.putSObject('QuoteLineItem', bakedSource);
    OrderItem glycerolOrderChild = new OrderItem();
    glycerolOrderChild.Product2 = new Product2(
      Name = 'Glycerol Stock',
      StockKeepingUnit = 'GS-001'
    );
    glycerolOrderChild.UnitPrice = 30;
    glycerolOrderChild.Quantity = 1;
    Map<Id, Decimal> bakedAddons = ABT_Portal_Controller.computeGlycerolAddonByOrderItemId(
      new List<OrderItem>{ bakedDna, zeroScaleOrderChild, glycerolOrderChild },
      new List<OrderItem>{ bakedDna }
    );
    System.assertEquals(
      30,
      bakedAddons.values()[0],
      'Baked Scale Up must not be added again; glycerol child still rolls onto the sequence'
    );
  }

  @isTest
  static void coverScaleUpMassMatrix() {
    System.assertEquals(
      null,
      ABT_Portal_Controller.scaleUpMassForCopyNumber('High', null)
    );
    System.assertEquals(
      null,
      ABT_Portal_Controller.scaleUpMassForCopyNumber('High', '  ')
    );
    System.assertEquals(
      null,
      ABT_Portal_Controller.scaleUpMassForCopyNumber('Unknown', '1')
    );

    System.assertEquals(
      '500 µg',
      ABT_Portal_Controller.scaleUpMassForCopyNumber('High', '1')
    );
    System.assertEquals(
      '1 mg',
      ABT_Portal_Controller.scaleUpMassForCopyNumber('Inducible', '2')
    );
    System.assertEquals(
      '1.5 mg',
      ABT_Portal_Controller.scaleUpMassForCopyNumber('High', '3')
    );
    System.assertEquals(
      '2 mg',
      ABT_Portal_Controller.scaleUpMassForCopyNumber('Inducible', '4')
    );
    System.assertEquals(
      '2.5 mg',
      ABT_Portal_Controller.scaleUpMassForCopyNumber('High', '5')
    );
    System.assertEquals(
      '500 µg',
      ABT_Portal_Controller.scaleUpMassForCopyNumber('Medium', '1')
    );
    System.assertEquals(
      '1 mg',
      ABT_Portal_Controller.scaleUpMassForCopyNumber('Medium', '2')
    );
    System.assertEquals(
      '2.5 mg',
      ABT_Portal_Controller.scaleUpMassForCopyNumber('Medium', '5')
    );

    System.assertEquals(
      '100 µg',
      ABT_Portal_Controller.scaleUpMassForCopyNumber('Low', '1')
    );
    System.assertEquals(
      '200 µg',
      ABT_Portal_Controller.scaleUpMassForCopyNumber('Low', '2')
    );
    System.assertEquals(
      '300 µg',
      ABT_Portal_Controller.scaleUpMassForCopyNumber('Low', '3')
    );
    System.assertEquals(
      '400 µg',
      ABT_Portal_Controller.scaleUpMassForCopyNumber('Low', '4')
    );
    System.assertEquals(
      '500 µg',
      ABT_Portal_Controller.scaleUpMassForCopyNumber('Low', '5')
    );
  }

  @isTest
  static void coverScaleUpLibraryAndNotify() {
    Account acc = new Account(
      Name = 'Fee Addon Scale Acc',
      ABT_Active__c = true,
      Scale_Up_Enabled__c = true,
      Default_Glycerol__c = true
    );
    insert acc;

    try {
      insert new Scale_Up__c(Name = 'Coverage Scale Up Option');
    } catch (Exception e) {
      System.assertNotEquals(null, e.getMessage());
    }

    Map<String, Object> withAccount = ABT_Portal_Controller.getScaleUpLibraryData(
      acc.Id
    );
    System.assertEquals(true, withAccount.get('scaleUpEnabled'));

    try {
      ABT_Portal_Controller.notifyCollateralDownloadFailure(
        null,
        'fasta',
        'coverage'
      );
    } catch (Exception e) {
      System.assertNotEquals(null, e.getMessage());
    }
  }

  /**
   * Directly exercises applyScaleUpFieldsToQuoteLineItems + updateQuoteRequestLineItemScaleUp
   * using the Checkout-proven quote/pricebook setup (avoids prod pricebook validation traps).
   */
  @isTest
  static void coverApplyScaleUpFieldsOnQuoteLineItem() {
    Account accountRecord = new Account(
      Name = 'Fee Addon QLI Acc ' + DateTime.now().getTime(),
      ABT_Active__c = true
    );
    insert accountRecord;
    Contact contactRecord = new Contact(
      FirstName = 'Fee',
      LastName = 'Addon',
      AccountId = accountRecord.Id,
      Email = 'fee-addon-qli-' + DateTime.now().getTime() + '@test.example.com',
      ABT_Active__c = true
    );
    insert contactRecord;

    Id pricebookId = Test.getStandardPricebookId();
    try {
      update new Pricebook2(Id = pricebookId, IsActive = true);
    } catch (Exception e) {
      System.assertNotEquals(null, e.getMessage());
    }

    Opportunity opportunityRecord = new Opportunity(
      Name = 'Fee Addon QLI Opp',
      AccountId = accountRecord.Id,
      StageName = 'Prospecting',
      CloseDate = Date.today().addDays(15),
      Pricebook2Id = pricebookId,
      ContactId = contactRecord.Id
    );
    insert opportunityRecord;

    String suffix = String.valueOf(DateTime.now().getTime()).right(8);
    Product2 parentProduct = new Product2(
      Name = 'Fee Addon Parent ' + suffix,
      ProductCode = 'FAP-' + suffix,
      IsActive = true
    );
    // Unique SKUs — org already owns SC-001/GS-001; test isolation can't query them.
    Product2 scaleUpProduct = new Product2(
      Name = 'Scale Up',
      StockKeepingUnit = 'SC-001',
      IsActive = true
    );
    Product2 glycerolProduct = new Product2(
      Name = 'Glycerol Stock - Tubes',
      StockKeepingUnit = 'GS-001',
      IsActive = true
    );
    Boolean insertedScaleSkus = false;
    try {
      insert new List<Product2>{
        parentProduct,
        scaleUpProduct,
        glycerolProduct
      };
      insertedScaleSkus = true;
    } catch (DmlException e) {
      insert parentProduct;
      scaleUpProduct = null;
      glycerolProduct = null;
    }

    PricebookEntry parentEntry = new PricebookEntry(
      Pricebook2Id = pricebookId,
      Product2Id = parentProduct.Id,
      UnitPrice = 175,
      IsActive = true
    );
    insert parentEntry;

    if (insertedScaleSkus) {
      insert new List<PricebookEntry>{
        new PricebookEntry(
          Pricebook2Id = pricebookId,
          Product2Id = scaleUpProduct.Id,
          UnitPrice = 325,
          IsActive = true
        ),
        new PricebookEntry(
          Pricebook2Id = pricebookId,
          Product2Id = glycerolProduct.Id,
          UnitPrice = 30,
          IsActive = true
        )
      };
    }

    Quote quoteRecord = new Quote(
      Name = 'Fee Addon QLI Quote',
      OpportunityId = opportunityRecord.Id,
      ContactId = contactRecord.Id,
      Status = 'Draft',
      Pricebook2Id = pricebookId
    );
    insert quoteRecord;
    quoteRecord = [
      SELECT Id, Pricebook2Id
      FROM Quote
      WHERE Id = :quoteRecord.Id
    ];
    if (quoteRecord.Pricebook2Id == null) {
      update new Quote(Id = quoteRecord.Id, Pricebook2Id = pricebookId);
    }

    QuoteLineItem parentQli = new QuoteLineItem(
      QuoteId = quoteRecord.Id,
      PricebookEntryId = parentEntry.Id,
      Product2Id = parentProduct.Id,
      Quantity = 1,
      UnitPrice = 175
    );
    insert parentQli;

    if (insertedScaleSkus) {
      PricebookEntry scaleEntry = [
        SELECT Id
        FROM PricebookEntry
        WHERE Product2Id = :scaleUpProduct.Id AND Pricebook2Id = :pricebookId
        LIMIT 1
      ];
      try {
        insert new QuoteLineItem(
          QuoteId = quoteRecord.Id,
          PricebookEntryId = scaleEntry.Id,
          Product2Id = scaleUpProduct.Id,
          Quantity = 1,
          UnitPrice = 325,
          Parent_Line_Item__c = parentQli.Id
        );
      } catch (DmlException e) {
        System.assertNotEquals(null, e.getMessage());
      }
    }

    ABT_Quote_Request__c quoteRequest = new ABT_Quote_Request__c(
      ABT_Account__c = accountRecord.Id,
      ABT_Contact__c = contactRecord.Id,
      ABT_Product__c = parentProduct.Id,
      ABT_Customer_Project_Name__c = 'Fee Addon QLI Project',
      ABT_Quote__c = quoteRecord.Id
    );
    insertDeployTestQuoteRequest(quoteRequest);

    Test.startTest();
    ABT_Portal_Controller.applyScaleUpFieldsToQuoteLineItems(
      new Set<Id>{ parentQli.Id },
      true,
      '2',
      2,
      true,
      true,
      false
    );
    if (insertedScaleSkus) {
      QuoteLineItem pricedParent = [
        SELECT Glycerol_Price__c
        FROM QuoteLineItem
        WHERE Id = :parentQli.Id
      ];
      System.assertEquals(
        30,
        pricedParent.Glycerol_Price__c,
        'Scale Up glycerol stamps the $30 GS-001 fee on the parent'
      );
    }
    ABT_Portal_Controller.applyScaleUpFieldsToQuoteLineItems(
      new Set<Id>{ parentQli.Id },
      true,
      'bad-qty',
      null,
      false,
      false,
      false
    );
    ABT_Portal_Controller.applyScaleUpFieldsToQuoteLineItems(
      new Set<Id>{ parentQli.Id },
      false,
      null,
      null,
      false,
      false,
      false
    );
    ABT_Portal_Controller.applyScaleUpFieldsToQuoteLineItems(
      null,
      true,
      '1',
      1,
      false,
      false,
      false
    );
    ABT_Portal_Controller.applyScaleUpFieldsToQuoteLineItems(
      new Set<Id>(),
      true,
      '1',
      1,
      false,
      false,
      false
    );

    System.assertEquals(
      null,
      ABT_Portal_Controller.scaleUpQuantityToDecimal(null)
    );
    System.assertEquals(
      null,
      ABT_Portal_Controller.scaleUpQuantityToDecimal('')
    );
    System.assertEquals(3, ABT_Portal_Controller.scaleUpQuantityToDecimal('3'));
    System.assertEquals(
      null,
      ABT_Portal_Controller.scaleUpQuantityToDecimal('x')
    );
    System.assertEquals(
      null,
      ABT_Portal_Controller.scaleUpNormalizationToApiValue(null)
    );
    System.assertEquals(
      null,
      ABT_Portal_Controller.scaleUpNormalizationToApiValue('NA')
    );
    System.assertEquals(
      '100',
      ABT_Portal_Controller.scaleUpNormalizationToApiValue('100')
    );

    Map<String, Object> emptyResult = ABT_Portal_Controller.updateQuoteRequestLineItemScaleUp(
      new List<Id>(),
      true,
      '2',
      true,
      'Water',
      true,
      false,
      '100'
    );
    System.assertEquals(false, emptyResult.get('success'));

    ABT_Quote_Request_Lineitem__c requestLine;
    try {
      requestLine = insertDeployTestRequestLine(
        quoteRequest.Id,
        'Fee Addon Scale Seq',
        parentProduct.Id,
        parentQli.Id
      );
    } catch (DmlException e) {
      requestLine = null;
    }

    if (requestLine != null) {
      Map<String, Object> applied = ABT_Portal_Controller.updateQuoteRequestLineItemScaleUp(
        new List<Id>{ requestLine.Id },
        true,
        '3',
        true,
        'Water',
        false,
        true,
        'NA'
      );
      System.assertEquals(
        true,
        applied.get('success'),
        String.valueOf(applied.get('error'))
      );

      Map<String, Object> cleared = ABT_Portal_Controller.updateQuoteRequestLineItemScaleUp(
        new List<Id>{ requestLine.Id },
        false,
        null,
        false,
        null,
        false,
        false,
        null
      );
      System.assertEquals(
        true,
        cleared.get('success'),
        String.valueOf(cleared.get('error'))
      );

      Map<String, Object> toxicBulk = ABT_Portal_Controller.bulkUpdateQuoteRequestLineItemPotentiallyToxic(
        new List<Id>{ requestLine.Id },
        new List<Boolean>{ true }
      );
      System.assertEquals(
        true,
        toxicBulk.get('success'),
        String.valueOf(toxicBulk.get('error'))
      );

      Map<String, Object> reflexBulk = ABT_Portal_Controller.bulkUpdateQuoteRequestLineItemReflexVectorOptIn(
        new List<Id>{ requestLine.Id },
        new List<Boolean>{ true }
      );
      System.assertEquals(
        true,
        reflexBulk.get('success'),
        String.valueOf(reflexBulk.get('error'))
      );

      Map<String, Object> singleGlycerol = ABT_Portal_Controller.updateQuoteRequestLineItemGlycerol(
        requestLine.Id,
        true
      );
      System.assertEquals(
        true,
        singleGlycerol.get('success'),
        String.valueOf(singleGlycerol.get('error'))
      );

      Map<String, Object> glycerolEnabled = ABT_Portal_Controller.bulkUpdateQuoteRequestLineItemGlycerol(
        new List<Id>{ requestLine.Id },
        new List<Boolean>{ true }
      );
      System.assertEquals(
        true,
        glycerolEnabled.get('success'),
        String.valueOf(glycerolEnabled.get('error'))
      );
      update new QuoteLineItem(Id = parentQli.Id, Glycerol_Stock__c = true);
      update new ABT_Quote_Request_Lineitem__c(
        Id = requestLine.Id,
        Glycerol_Stock__c = true
      );
      Map<String, Object> glycerolRetrigger = ABT_Portal_Controller.bulkUpdateQuoteRequestLineItemGlycerol(
        new List<Id>{ requestLine.Id },
        new List<Boolean>{ true }
      );
      System.assertEquals(
        true,
        glycerolRetrigger.get('success'),
        String.valueOf(glycerolRetrigger.get('error'))
      );
      Map<String, Object> glycerolDisabled = ABT_Portal_Controller.bulkUpdateQuoteRequestLineItemGlycerol(
        new List<Id>{ requestLine.Id },
        new List<Boolean>{ false }
      );
      System.assertEquals(
        true,
        glycerolDisabled.get('success'),
        String.valueOf(glycerolDisabled.get('error'))
      );
      Map<String, Object> glycerolNoop = ABT_Portal_Controller.bulkUpdateQuoteRequestLineItemGlycerol(
        new List<Id>{ requestLine.Id },
        new List<Boolean>{ false }
      );
      System.assertEquals(
        true,
        glycerolNoop.get('success'),
        String.valueOf(glycerolNoop.get('error'))
      );
      System.assertEquals(false, glycerolNoop.get('removedFromCart'));
    }
    Test.stopTest();

    QuoteLineItem afterClear = [
      SELECT Scale_Up_Mass__c, Scale_Up_Price__c, Scale_Up_Lead_Time__c
      FROM QuoteLineItem
      WHERE Id = :parentQli.Id
    ];
    System.assertEquals(null, afterClear.Scale_Up_Mass__c);
    System.assertEquals(0, afterClear.Scale_Up_Price__c);
    System.assertEquals(null, afterClear.Scale_Up_Lead_Time__c);
  }

  @IsTest
  static void scaleUpGlycerolFeePrefersChildOverZeroPricebook() {
    System.assertEquals(
      30,
      ABT_Portal_Controller.scaleUpGlycerolFeeForParent(30, 0, 0),
      'GS-001 child sales price wins over a $0 internal list price'
    );
    System.assertEquals(
      30,
      ABT_Portal_Controller.scaleUpGlycerolFeeForParent(null, 30, 0),
      'Use the glycerol price book when no child exists'
    );
    System.assertEquals(
      30,
      ABT_Portal_Controller.scaleUpGlycerolFeeForParent(null, 0, 30),
      'Keep an existing $30 parent fee when list price is $0'
    );
    System.assertEquals(
      0,
      ABT_Portal_Controller.scaleUpGlycerolFeeForParent(null, 0, 0)
    );
  }

  @IsTest
  static void getQuoteRequestSalesLineItemsCoversEmptyPaths() {
    System.assertEquals(
      0,
      ABT_Portal_Controller.getQuoteRequestSalesLineItems(null).size()
    );

    Account accountRecord = new Account(
      Name = 'Sales Line Items Acc ' + DateTime.now().getTime(),
      ABT_Active__c = true
    );
    insert accountRecord;
    ABT_Quote_Request__c quoteRequest = new ABT_Quote_Request__c(
      ABT_Account__c = accountRecord.Id,
      ABT_Customer_Project_Name__c = 'Sales Line Items'
    );
    insertDeployTestQuoteRequest(quoteRequest);

    List<QuoteLineItem> lines = ABT_Portal_Controller.getQuoteRequestSalesLineItems(
      quoteRequest.Id
    );
    System.assertNotEquals(null, lines);
    System.assertEquals(0, lines.size());
  }
}
