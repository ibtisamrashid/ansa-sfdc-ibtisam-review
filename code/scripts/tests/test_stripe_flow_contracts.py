"""Offline branch checks against actual Flow XML, using synthetic values.

This checks connector routing and metadata contracts, not Salesforce execution.
Run with --baseline to check committed main instead of the working tree.
"""
from pathlib import Path
import re
import subprocess
import sys
import unittest
import xml.etree.ElementTree as ET

BASELINE = '--baseline' in sys.argv
if BASELINE:
    sys.argv.remove('--baseline')
ROOT = Path(__file__).resolve().parents[2]
BASE_REF = subprocess.check_output(['git', 'merge-base', 'HEAD', 'origin/main'], cwd=ROOT, text=True).strip()
NS = {'m': 'http://soap.sforce.com/2006/04/metadata'}


def metadata(relative):
    name = 'force-app/main/default/' + relative
    if BASELINE:
        content = subprocess.check_output(['git', 'show', BASE_REF + ':' + name], cwd=ROOT)
    else:
        content = (ROOT / name).read_bytes()
    return ET.fromstring(content)


def split_args(text):
    depth = 0
    start = 0
    result = []
    for index, character in enumerate(text):
        if character == '(':
            depth += 1
        elif character == ')':
            depth -= 1
        elif character == ',' and depth == 0:
            result.append(text[start:index].strip())
            start = index + 1
    return result + [text[start:].strip()]


class Flow:
    def __init__(self, name):
        self.root = metadata('flows/' + name + '.flow-meta.xml')
        self.nodes = {e.findtext('m:name', namespaces=NS): e for e in self.root
                      if e.find('m:name', NS) is not None}
        self.formulas = {e.findtext('m:name', namespaces=NS): e.findtext('m:expression', namespaces=NS)
                         for e in self.root.findall('m:formulas', NS)}

    def expression(self, text, values):
        text = text.strip()
        if text in self.formulas:
            return self.expression(self.formulas[text], values)
        if text.startswith('(') and text.endswith(')'):
            text = text[1:-1].strip()
        comparison = re.fullmatch(r'(\{![^}]+\})\s*=\s*(\{![^}]+\})', text)
        if comparison:
            return self.expression(comparison.group(1), values) == self.expression(comparison.group(2), values)
        if text.startswith('{!') and text.endswith('}'):
            return values.get(text[2:-1])
        if text.startswith(chr(34)) and text.endswith(chr(34)):
            return text[1:-1]
        match = re.fullmatch(r'(IF|NOT|ISBLANK|AND|ISPICKVAL)\((.*)\)', text, flags=re.S)
        if match:
            name, inner = match.groups()
            args = split_args(inner)
            if name == 'IF':
                return self.expression(args[1] if self.expression(args[0], values) else args[2], values)
            if name == 'AND':
                return all(self.expression(arg, values) for arg in args)
            if name == 'ISPICKVAL':
                return self.expression(args[0], values) == self.expression(args[1], values)
            value = self.expression(args[0], values)
            return not value if name == 'NOT' else value is None or value == ''
        return values.get(text)

    def value(self, element, values):
        child = next(iter(element))
        kind = child.tag.rsplit('}', 1)[-1]
        if kind == 'elementReference':
            return self.expression(child.text, values)
        if kind == 'booleanValue':
            return child.text == 'true'
        return child.text or ''

    def branch(self, name, values):
        node = self.nodes[name]
        for rule in node.findall('m:rules', NS):
            results = []
            for condition in rule.findall('m:conditions', NS):
                left = self.expression(condition.findtext('m:leftValueReference', namespaces=NS), values)
                right = self.value(condition.find('m:rightValue', NS), values)
                operator = condition.findtext('m:operator', namespaces=NS)
                if operator == 'EqualTo':
                    results.append(left == right)
                elif operator == 'IsNull':
                    results.append((left is None) == right)
                elif operator == 'IsBlank':
                    results.append((left is None or left == '') == right)
                else:
                    raise AssertionError('Unsupported condition in offline runner: ' + operator)
            logic = rule.findtext('m:conditionLogic', namespaces=NS)
            if logic not in ('and', 'or'):
                raise AssertionError('Unsupported condition logic: ' + logic)
            if (all(results) if logic == 'and' else any(results)):
                return rule.findtext('m:connector/m:targetReference', namespaces=NS)
        return node.findtext('m:defaultConnector/m:targetReference', namespaces=NS)

    def after_action(self, name, values):
        target = self.nodes[name].findtext('m:connector/m:targetReference', namespaces=NS)
        if target is not None and self.nodes[target].tag.endswith('decisions'):
            return self.branch(target, values)
        return target


NAMES = ('ABT_Generate_Stripe_Payment_Link', 'ABT_Get_Consolidated_Product_Prices',
         'ABT_Subflow_Create_Stripe_Shipping_Cost', 'ABT_Subflow_Create_Stripe_Tax_Rate')


def canonical(element):
    return (element.tag, (element.text or '').strip(), tuple(canonical(e) for e in element))


def original(name):
    return ET.fromstring(subprocess.check_output(['git', 'show',
        BASE_REF + ':force-app/main/default/flows/' + name + '.flow-meta.xml'], cwd=ROOT))


class StripeFlowContracts(unittest.TestCase):
    def test_existing_stripe_request_parameters_are_unchanged(self):
        for name in NAMES:
            flow=Flow(name)
            for action in original(name).findall('m:actionCalls', NS):
                key=action.findtext('m:name', namespaces=NS)
                with self.subTest(flow=name, action=key):
                    self.assertEqual([canonical(e) for e in action.findall('m:inputParameters',NS)],
                        [canonical(e) for e in flow.nodes[key].findall('m:inputParameters',NS)])

    def test_financial_formulas_and_descriptions_are_unchanged(self):
        for name in NAMES:
            flow=Flow(name)
            for node in original(name):
                key=node.findtext('m:name',namespaces=NS)
                kind=node.tag.rsplit('}',1)[-1]
                if kind=='textTemplates' or (kind=='formulas' and key not in ('ErrorMessage','StripeError','WorkerClaimIsValid')):
                    with self.subTest(flow=name,formula=key):
                        self.assertEqual(canonical(node),canonical(flow.nodes[key]))

    def test_worker_claim_uses_verified_flow_formula_functions(self):
        # EXACT blocks this Flow from activating. Equality is the supported operator.
        expression=Flow(NAMES[0]).formulas['WorkerClaimIsValid']
        functions=set(re.findall(r'\b([A-Z_][A-Z0-9_]*)\s*\(',expression))
        self.assertFalse(functions-{'AND','NOT','ISBLANK','ISPICKVAL'},
            'Worker claim uses an unverified or unsupported Flow formula function')

    def test_unowned_execution_cannot_create_an_invoice(self):
        flow=Flow(NAMES[0])
        for worker, stored, status in [(None,'707synthetic','Processing'),
                ('707other','707synthetic','Processing'),('707synthetic','707synthetic','Queued')]:
            self.assertEqual('Reject_Unowned_Execution',flow.branch('Check_Worker_Ownership',{
                'workerJobId':worker,'Get_Invoice_Record.ABT_Stripe_Worker_Id__c':stored,
                'Get_Invoice_Record.ABT_Stripe_Processing_Status__c':status}))
        self.assertEqual('Check_Already_Has_Stripe_Invoice',flow.branch('Check_Worker_Ownership',{
            'workerJobId':'707synthetic','Get_Invoice_Record.ABT_Stripe_Worker_Id__c':'707synthetic',
            'Get_Invoice_Record.ABT_Stripe_Processing_Status__c':'Processing'}))

    def test_partial_consolidated_invoice_cannot_reach_payment(self):
        flow=Flow(NAMES[0])
        self.assertIsNone(flow.branch('Check_Consolidated_Completion',{'FlowError':'failure','StripeInvoiceId':'in_synthetic'}))
        self.assertIsNone(flow.branch('Check_Consolidated_Completion',{'FlowError':None,'StripeInvoiceId':None}))
        self.assertEqual('Check_Payment_Method',flow.branch('Check_Consolidated_Completion',
            {'FlowError':None,'StripeInvoiceId':'in_synthetic'}))

    def test_invoice_card_guard_precedes_original_pay(self):
        flow=Flow(NAMES[0]); guard=flow.nodes['Verify_Invoice_Payment_Method']
        self.assertEqual('Post_Invoices_Pay',guard.findtext('m:connector/m:targetReference',namespaces=NS))
        self.assertEqual('Update_Error_on_Invoice',guard.findtext('m:faultConnector/m:targetReference',namespaces=NS))
        sources=[n.findtext('m:name',namespaces=NS) for n in flow.root
            if n.findtext('m:connector/m:targetReference',namespaces=NS)=='Post_Invoices_Pay']
        self.assertEqual(['Verify_Invoice_Payment_Method'],sources)

    def test_stripe_actions_remain_in_callout_transaction(self):
        for name in NAMES:
            for node in Flow(name).root.findall('m:actionCalls',NS):
                if (node.findtext('m:actionName',namespaces=NS) or '').startswith('stripeGC'):
                    self.assertEqual('CurrentTransaction',node.findtext('m:flowTransactionModel',namespaces=NS))

    def test_catalog_cleanup_failure_can_continue_original_invoice(self):
        for name in NAMES[:2]:
            flow=Flow(name)
            for node in original(name).findall('m:actionCalls',NS):
                key=node.findtext('m:name',namespaces=NS)
                if 'Deactivate' not in key: continue
                warning=flow.nodes[key].findtext('m:faultConnector/m:targetReference',namespaces=NS)
                self.assertIsNotNone(warning)
                self.assertEqual(node.findtext('m:connector/m:targetReference',namespaces=NS),
                    flow.nodes[warning].findtext('m:connector/m:targetReference',namespaces=NS))

    def test_failure_retains_existing_stripe_invoice_reference(self):
        for name in NAMES[:2]:
            node=Flow(name).nodes['Preserve_Stripe_Failure']
            fields={e.findtext('m:field',namespaces=NS) for e in node.findall('m:inputAssignments',NS)}
            self.assertIn('ABT_Stripe_Invoice_Id__c',fields)
            self.assertIn('ABT_Stripe_Error__c',fields)
            self.assertIn('Sent_to_Stripe__c',fields)

    def test_invoice_release_requires_separate_activation(self):
        # FlowDefinition version pointers are org-specific and excluded from deployment.
        # The deployable Flow status must leave activation to the release owner.
        ignore=(ROOT / '.forceignore').read_text()
        self.assertIn('force-app/main/default/flowDefinitions/',ignore.splitlines())
        for name in (NAMES[0],'ABT_Create_Payment_Link_On_Invoice'):
            self.assertEqual('Draft',Flow(name).root.findtext('m:status',namespaces=NS))

    def test_manual_invoice_action_uses_guarded_dispatcher(self):
        flow=Flow('ABT_Manually_Generate_Stripe_Payment_Link')
        self.assertEqual('Draft',flow.root.findtext('m:status',namespaces=NS),
            'Manual invoice activation requires release-owner approval')
        self.assertEqual('Enqueue_Stripe_Creation',flow.branch('Required_Fields',{
            'Get_Invoice.ABT_Billing_Account_Id__c':'synthetic_account',
            'Get_Invoice.ABT_Payment_Method__c':'Purchase Order',
            'Get_Invoice.ABT_Stripe_Payment_Method_Id__c':None}))
        action=flow.nodes['Enqueue_Stripe_Creation']
        self.assertEqual('ABT_StripeInvoiceDispatcher',action.findtext('m:actionName',namespaces=NS))
        self.assertEqual('Get_Queued_Invoice',action.findtext('m:connector/m:targetReference',namespaces=NS))
        self.assertEqual('Set_Queue_Failure',action.findtext('m:faultConnector/m:targetReference',namespaces=NS))
        self.assertFalse(flow.root.findall('m:subflows',NS),'Manual entry cannot bypass committed ownership')
        # Required billing fields and payment eligibility are preserved exactly.
        before=next(n for n in original('ABT_Manually_Generate_Stripe_Payment_Link').findall('m:decisions',NS)
            if n.findtext('m:name',namespaces=NS)=='Required_Fields')
        self.assertEqual([canonical(n) for n in before.findall('.//m:conditions',NS)],
            [canonical(n) for n in flow.nodes['Required_Fields'].findall('.//m:conditions',NS)])

    def test_manual_operator_permissions_are_scoped_and_read_only(self):
        root=metadata('permissionsets/ABT_Manual_Stripe_Invoice_Operator.permissionset-meta.xml')
        self.assertLessEqual(len(root.findtext('m:description',default='',namespaces=NS)),255,
            'Salesforce permission-set descriptions are limited to 255 characters')
        fields=root.findall('m:fieldPermissions',NS)
        self.assertEqual({
            'ABT_Invoice__c.ABT_Stripe_Worker_Id__c',
            'ABT_Invoice__c.ABT_Stripe_Processing_Status__c',
            'ABT_Invoice__c.ABT_Stripe_Retry_Count__c',
            'ABT_Invoice__c.ABT_Stripe_Invoice_Total__c',
        },{node.findtext('m:field',namespaces=NS) for node in fields})
        for node in fields:
            self.assertEqual('true',node.findtext('m:readable',namespaces=NS))
            self.assertEqual('false',node.findtext('m:editable',namespaces=NS))
        self.assertEqual(['ABT_StripeInvoiceDispatcher'],[
            node.findtext('m:apexClass',namespaces=NS)
            for node in root.findall('m:classAccesses',NS)
            if node.findtext('m:enabled',namespaces=NS)=='true'])
        for kind in ('objectPermissions','userPermissions','flowAccesses','recordTypeVisibilities'):
            self.assertFalse(root.findall('m:'+kind,NS),kind+' must remain separately authorized')

    def test_manual_result_does_not_claim_invoice_was_created(self):
        flow=Flow('ABT_Manually_Generate_Stripe_Payment_Link')
        for status in ('Queued','Processing'):
            self.assertEqual('Success_Message',flow.branch('Check_for_Subflow_Failure',
                {'Get_Queued_Invoice.ABT_Stripe_Processing_Status__c':status}))
        for status in (None,'Review','Failed','Created'):
            self.assertEqual('Set_Queue_Failure',flow.branch('Check_for_Subflow_Failure',
                {'Get_Queued_Invoice.ABT_Stripe_Processing_Status__c':status}))
        message=flow.nodes['Success_Message'].findtext('m:fields/m:fieldText',namespaces=NS)
        self.assertIn('queued',message)
        self.assertNotIn('created successfully',message)

    def test_subflows_do_not_use_unsupported_fault_connectors(self):
        # FlowSubflow has no faultConnector property in the Metadata API.
        # XML well-formedness alone does not validate Salesforce metadata types.
        for name in NAMES:
            flow=Flow(name)
            for node in flow.root.findall('m:subflows',NS):
                with self.subTest(flow=name,subflow=node.findtext('m:name',namespaces=NS)):
                    self.assertIsNone(node.find('m:faultConnector',NS),
                        'Salesforce rejects faultConnector on FlowSubflow')

    def test_no_dangling_connectors(self):
        for name in NAMES + ('ABT_Manually_Generate_Stripe_Payment_Link',):
            flow=Flow(name)
            for target in flow.root.findall('.//m:targetReference',NS):
                self.assertIn(target.text,flow.nodes)


if __name__ == '__main__':
    unittest.main(verbosity=2)
