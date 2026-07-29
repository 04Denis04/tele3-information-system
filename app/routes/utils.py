def get_page(args):
    try:
        return max(1, int(args.get('page', 1)))
    except (TypeError, ValueError):
        return 1