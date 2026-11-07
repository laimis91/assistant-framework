from dateutil import parser


def tidy_cell(value):
    value = value.strip()
    try:
        return parser.parse(value, dayfirst=False).date().isoformat()
    except (ValueError, OverflowError):
        return value
