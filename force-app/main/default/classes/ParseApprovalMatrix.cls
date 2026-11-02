public class ParseApprovalMatrix {
    public class ParsedRequest {
        @InvocableVariable
        public Boolean isValid;

        @InvocableVariable
        public String errorMessage;

        @InvocableVariable
        public String rawText;

        @InvocableVariable
        public String requestType;

        @InvocableVariable
        public String division;

        @InvocableVariable
        public String category;

        @InvocableVariable
        public String brand;

        @InvocableVariable
        public String productCategory;

        @InvocableVariable
        public Decimal salesDiscount;

        @InvocableVariable
        public Decimal discountPercentage;

        @InvocableVariable
        public Decimal discountMax;

        @InvocableVariable
        public Decimal abovePolicyDiscountPercentage;

        @InvocableVariable
        public String approvalLevel;

        @InvocableVariable
        public Decimal approvalMax;

        @InvocableVariable
        public String approvalGreaterThanMax;

        @InvocableVariable
        public String abovePolicyLevel;

        @InvocableVariable
        public Decimal gm;

        @InvocableVariable
        public Decimal agm;

        @InvocableVariable
        public Decimal rm;
    }

    private static final Set<String> ALLOWED_LABELS = new Set<String>{
        'Request Type',
        'Division',
        'Category',
        'Brand',
        'Product Category',
        'Sales Discount',
        'Discount Percentage',
        'Discount Max',
        'Above Policy Discount Percentage',
        'Approval Level',
        'Approval Max',
        'Approval Greater Than Max',
        'Above Policy Level',
        'GM',
        'AGM',
        'RM'
    };

    public static ParsedRequest parse(String rawText) {
        ParsedRequest result = new ParsedRequest();
        result.isValid = false;
        result.rawText = rawText;

        List<String> errors = new List<String>();
        if (String.isBlank(rawText)) {
            result.errorMessage = 'The TXT file is empty.';
            return result;
        }

        Map<String, String> values = new Map<String, String>();
        for (String line : rawText.replace('\r\n', '\n').replace('\r', '\n').split('\n')) {
            String trimmedLine = line.trim();
            if (trimmedLine == '') {
                continue;
            }

            Integer separator = trimmedLine.indexOf(':');
            if (separator <= 0) {
                errors.add('Each non-empty line must use the format "Label: value".');
                continue;
            }

            String label = trimmedLine.substring(0, separator).trim();
            String value = trimmedLine.substring(separator + 1).trim();
            if (!ALLOWED_LABELS.contains(label)) {
                errors.add('Unrecognized label: ' + label + '.');
            } else if (values.containsKey(label)) {
                errors.add('Duplicate label: ' + label + '.');
            } else if (value == '') {
                errors.add(label + ' must have a value.');
            } else {
                values.put(label, value);
            }
        }

        String requestType = values.get('Request Type');
        if (requestType == null) {
            errors.add('Request Type is required.');
        } else if (requestType.equalsIgnoreCase('Power')) {
            requestType = 'Power';
            validateRequired(
                values,
                new List<String>{
                    'Division',
                    'Category',
                    'Brand',
                    'Product Category',
                    'Sales Discount',
                    'Discount Percentage',
                    'Discount Max',
                    'Above Policy Discount Percentage',
                    'Approval Level',
                    'Approval Max',
                    'Approval Greater Than Max',
                    'Above Policy Level'
                },
                errors
            );
        } else if (requestType.equalsIgnoreCase('Lighting')) {
            requestType = 'Lighting';
            validateRequired(values, new List<String>{ 'Product Category', 'GM', 'AGM', 'RM' }, errors);
        } else {
            errors.add('Request Type must be Power or Lighting.');
        }

        if (requestType == 'Power') {
            result.salesDiscount = parseNumber(values.get('Sales Discount'), 'Sales Discount', errors);
            result.discountPercentage = parseNumber(
                values.get('Discount Percentage'),
                'Discount Percentage',
                errors
            );
            result.discountMax = parseNumber(values.get('Discount Max'), 'Discount Max', errors);
            result.abovePolicyDiscountPercentage = parseNumber(
                values.get('Above Policy Discount Percentage'),
                'Above Policy Discount Percentage',
                errors
            );
            result.approvalMax = parseNumber(values.get('Approval Max'), 'Approval Max', errors);
        } else if (requestType == 'Lighting') {
            result.gm = parseNumber(values.get('GM'), 'GM', errors);
            result.agm = parseNumber(values.get('AGM'), 'AGM', errors);
            result.rm = parseNumber(values.get('RM'), 'RM', errors);
        }

        if (!errors.isEmpty()) {
            result.errorMessage = String.join(errors, ' ');
            return result;
        }

        result.isValid = true;
        result.requestType = requestType;
        result.division = values.get('Division');
        result.category = values.get('Category');
        result.brand = values.get('Brand');
        result.productCategory = values.get('Product Category');
        result.approvalLevel = values.get('Approval Level');
        result.approvalGreaterThanMax = values.get('Approval Greater Than Max');
        result.abovePolicyLevel = values.get('Above Policy Level');
        return result;
    }

    private static void validateRequired(
        Map<String, String> values,
        List<String> requiredLabels,
        List<String> errors
    ) {
        for (String label : requiredLabels) {
            if (!values.containsKey(label)) {
                errors.add(label + ' is required.');
            }
        }
    }

    private static Decimal parseNumber(String value, String label, List<String> errors) {
        if (value == null) {
            return null;
        }

        String normalized = value.replace(',', '').replace('$', '').replace('%', '').trim();
        try {
            return Decimal.valueOf(normalized);
        } catch (TypeException e) {
            errors.add(label + ' must be numeric.');
            return null;
        }
    }
}