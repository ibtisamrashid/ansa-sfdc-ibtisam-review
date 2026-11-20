import { analyzeCartQuoteOrderability } from 'c/abtQuoteCheckoutUtils';

const internalAccountId = '001VH000006eZjdYAE';
const otherAccountId = '001000000000001AAA';

function quote(accountId, classification) {
    return {
        AccountId: accountId,
        Opportunity: { AccountId: accountId },
        quoteLineItems: [{
            Product2: { Name: 'Clonal DNA' },
            Related_Sequence__r: { Sequence_Classification__c: classification },
        }],
    };
}

describe('cart quote orderability', () => {
    it('allows an NCP-only quote for the internal account', () => {
        expect(analyzeCartQuoteOrderability([
            quote(internalAccountId, 'Not Currently Possible'),
        ])).toEqual({
            hasNotCurrentlyPossibleSequences: false,
            hasOnlyNotCurrentlyPossibleSequences: false,
            hasBlockedCartQuotes: false,
        });
    });

    it('continues to block an NCP-only quote for another account', () => {
        expect(analyzeCartQuoteOrderability([
            quote(otherAccountId, 'Not Currently Possible'),
        ])).toEqual({
            hasNotCurrentlyPossibleSequences: true,
            hasOnlyNotCurrentlyPossibleSequences: true,
            hasBlockedCartQuotes: true,
        });
    });

    it('uses the opportunity account when the quote account differs', () => {
        const q = quote(otherAccountId, 'Not Currently Possible');
        q.Opportunity.AccountId = internalAccountId;
        expect(analyzeCartQuoteOrderability([q]).hasBlockedCartQuotes).toBe(false);
    });
});
