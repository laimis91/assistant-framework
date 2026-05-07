namespace MemoryGraph.Graph;

internal static class KnowledgeGraphQueries
{
    public static List<Entity> FindByAlias(IEnumerable<Entity> entities, string alias)
    {
        return ProjectIdentityResolver.FindProjectsByAlias(entities, alias);
    }

    public static List<Entity> Search(IEnumerable<Entity> entities, string query, EntityType[]? types = null)
    {
        var results = new List<Entity>();
        var expression = SearchExpression.Parse(query);

        foreach (var entity in entities)
        {
            if (types is not null && !types.Contains(entity.Type))
            {
                continue;
            }

            if (expression.Matches(entity))
            {
                results.Add(entity);
            }
        }

        return results;
    }

    private sealed class SearchExpression
    {
        private readonly List<List<SearchTerm>> _groups;

        private SearchExpression(List<List<SearchTerm>> groups)
        {
            _groups = groups;
        }

        public static SearchExpression Parse(string query)
        {
            var groups = new List<List<SearchTerm>> { new() };
            var negateNext = false;

            foreach (var token in Tokenize(query))
            {
                if (!token.IsQuoted && token.Text == "OR")
                {
                    groups.Add(new());
                    negateNext = false;
                    continue;
                }

                if (!token.IsQuoted && token.Text == "AND")
                {
                    continue;
                }

                if (!token.IsQuoted && token.Text == "NOT")
                {
                    negateNext = true;
                    continue;
                }

                groups[^1].Add(new SearchTerm(token.Text, negateNext));
                negateNext = false;
            }

            return new SearchExpression(groups.Where(g => g.Count > 0).ToList());
        }

        public bool Matches(Entity entity)
        {
            if (_groups.Count == 0)
            {
                return false;
            }

            var searchableText = $"{entity.Name}\n{string.Join("\n", entity.Observations)}";
            return _groups.Any(group => group.All(term => term.Matches(searchableText)));
        }

        private static IEnumerable<SearchToken> Tokenize(string query)
        {
            var tokenizer = new SearchTokenizer();

            foreach (var c in query)
            {
                var token = tokenizer.Read(c);
                if (token.HasValue && HasSearchText(token.Value))
                {
                    yield return token.Value;
                }
            }

            var finalToken = tokenizer.Flush();
            if (finalToken.HasValue && HasSearchText(finalToken.Value))
            {
                yield return finalToken.Value;
            }
        }

        private static bool HasSearchText(SearchToken token)
        {
            return !string.IsNullOrWhiteSpace(token.Text);
        }
    }

    private readonly record struct SearchToken(string Text, bool IsQuoted);

    private sealed class SearchTokenizer
    {
        private readonly List<char> _current = new();
        private bool _inQuote;
        private bool _tokenWasQuoted;

        public SearchToken? Read(char c)
        {
            if (c == '"')
            {
                return ReadQuote();
            }

            if (char.IsWhiteSpace(c) && !_inQuote)
            {
                return ReadWhitespace();
            }

            _current.Add(c);
            return null;
        }

        public SearchToken? Flush()
        {
            return _current.Count > 0 ? CreateToken(_tokenWasQuoted) : null;
        }

        private SearchToken? ReadQuote()
        {
            if (_inQuote)
            {
                var token = CreateToken(isQuoted: true);
                _inQuote = false;
                _tokenWasQuoted = false;
                return token;
            }

            var pending = Flush();
            _inQuote = true;
            _tokenWasQuoted = true;
            return pending;
        }

        private SearchToken? ReadWhitespace()
        {
            var token = Flush();
            _tokenWasQuoted = false;
            return token;
        }

        private SearchToken CreateToken(bool isQuoted)
        {
            var token = new SearchToken(new string(_current.ToArray()), isQuoted);
            _current.Clear();
            return token;
        }
    }

    private readonly record struct SearchTerm(string Text, bool Negated)
    {
        public bool Matches(string searchableText)
        {
            var contains = searchableText.Contains(Text, StringComparison.OrdinalIgnoreCase);
            return Negated ? !contains : contains;
        }
    }
}
