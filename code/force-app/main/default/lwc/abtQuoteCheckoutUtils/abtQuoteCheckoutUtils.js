import { isPortalFeeAddonProduct } from 'c/abtProductNameUtils';

export const SEQUENCE_CLASSIFICATION_NOT_POSSIBLE = 'Not Currently Possible';
export const INTERNAL_NCP_ORDER_ACCOUNT_ID = '001VH000006eZjdYAE';

export const CHECKOUT_NO_ORDERABLE_LINES_MESSAGE =
    'This quote has no orderable sequences. Sequences assessed as Not Currently Possible cannot be included in an order.';

export const CHECKOUT_CART_NO_ORDERABLE_LINES_MESSAGE =
    'One or more quotes contain only sequences that are Not Currently Possible and cannot be ordered.';

export const CHECKOUT_CUSTOMER_MESSAGE =
    'We encountered an issue processing your request. We\'ve alerted our technical teams and they will be reaching out to you within 24 hours with a fix to this issue.';

export function isDeletedQuoteLineItem(li) {
    return li?.Was_Deleted__c === true || li?.was_Deleted__c === true;
}

export function quoteLineItemsFromQuote(q) {
    if (!q) {
        return [];
    }
    const raw = q.quoteLineItems ?? q.QuoteLineItems;
    const lines = Array.isArray(raw) ? raw : [];
    return lines.filter(li => !isDeletedQuoteLineItem(li));
}

export function sequenceClassificationFromLine(li) {
    return (
        li?.Related_Sequence__r?.Sequence_Classification__c
        ?? li?.related_Sequence__r?.Sequence_Classification__c
        ?? ''
    ).trim();
}

export function isNotCurrentlyPossibleLine(li) {
    return sequenceClassificationFromLine(li) === SEQUENCE_CLASSIFICATION_NOT_POSSIBLE;
}

export function analyzeCartQuoteOrderability(quotesData) {
    let hasNotCurrentlyPossibleSequences = false;
    let pricedLineCount = 0;
    let orderableLineCount = 0;
    let blockedQuoteCount = 0;

    for (const q of quotesData || []) {
        const accountId = q?.Opportunity?.AccountId ?? q?.AccountId;
        const allowsNcp = accountId === INTERNAL_NCP_ORDER_ACCOUNT_ID;
        const lines = quoteLineItemsFromQuote(q);
        if (!lines.length) {
            continue;
        }

        let quoteOrderableCount = 0;
        let quoteSequenceLineCount = 0;
        for (const li of lines) {
            if (isPortalFeeAddonProduct(li)) {
                continue;
            }
            quoteSequenceLineCount += 1;
            pricedLineCount += 1;
            if (isNotCurrentlyPossibleLine(li) && !allowsNcp) {
                hasNotCurrentlyPossibleSequences = true;
            } else {
                orderableLineCount += 1;
                quoteOrderableCount += 1;
            }
        }

        if (quoteSequenceLineCount > 0 && quoteOrderableCount === 0) {
            blockedQuoteCount += 1;
        }
    }

    return {
        hasNotCurrentlyPossibleSequences,
        hasOnlyNotCurrentlyPossibleSequences: pricedLineCount > 0 && orderableLineCount === 0,
        hasBlockedCartQuotes: blockedQuoteCount > 0,
    };
}
