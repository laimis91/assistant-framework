using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;
using Microsoft.CodeAnalysis.CSharp.Syntax;

namespace CognitiveComplexity;

/// <summary>
/// Calculates cognitive complexity for each method in a C# syntax tree.
/// 
/// SonarSource rules:
///   1. +1 for each break in linear flow
///   2. +nesting for nested flow-breaking structures
///   3. Ignore shorthand structures (e.g. switch cases don't each add +1)
///
/// Reference: https://www.sonarsource.com/docs/CognitiveComplexity.pdf
/// </summary>
public sealed class CognitiveComplexityWalker : CSharpSyntaxWalker
{
    private readonly List<FunctionComplexity> _results = [];

    public IReadOnlyList<FunctionComplexity> Results => _results;

    public static IReadOnlyList<FunctionComplexity> Analyze(string source)
    {
        var tree = CSharpSyntaxTree.ParseText(source);
        var walker = new CognitiveComplexityWalker();
        walker.Visit(tree.GetRoot());
        return walker.Results;
    }

    // ── Method-level entry points ───────────────────────────────────────

    public override void VisitMethodDeclaration(MethodDeclarationSyntax node)
    {
        AnalyzeFunction(node.Identifier.Text, node.GetLocation(), node.Body, node.ExpressionBody);
    }

    public override void VisitConstructorDeclaration(ConstructorDeclarationSyntax node)
    {
        var name = $"{node.Identifier.Text} (ctor)";
        AnalyzeFunction(name, node.GetLocation(), node.Body, node.ExpressionBody);
    }

    public override void VisitDestructorDeclaration(DestructorDeclarationSyntax node)
    {
        AnalyzeFunction($"~{node.Identifier.Text}", node.GetLocation(), node.Body, null);
    }

    public override void VisitPropertyDeclaration(PropertyDeclarationSyntax node)
    {
        // Analyze property accessors (get/set) if they have bodies
        if (node.AccessorList is not null)
        {
            foreach (var accessor in node.AccessorList.Accessors)
            {
                if (accessor.Body is not null || accessor.ExpressionBody is not null)
                {
                    var name = $"{node.Identifier.Text}.{accessor.Keyword.Text}";
                    AnalyzeFunction(name, accessor.GetLocation(), accessor.Body, accessor.ExpressionBody);
                }
            }
        }

        // Expression-bodied property (=> expr)
        if (node.ExpressionBody is not null)
        {
            AnalyzeFunction(node.Identifier.Text, node.GetLocation(), null, node.ExpressionBody);
        }
    }

    public override void VisitOperatorDeclaration(OperatorDeclarationSyntax node)
    {
        AnalyzeFunction($"operator {node.OperatorToken.Text}", node.GetLocation(), node.Body, node.ExpressionBody);
    }

    // ── Core analysis ───────────────────────────────────────────────────

    private void AnalyzeFunction(string name, Location location, BlockSyntax? body, ArrowExpressionClauseSyntax? exprBody)
    {
        var line = location.GetLineSpan().StartLinePosition.Line + 1;
        var result = new FunctionComplexity(name, line);

        if (body is not null)
        {
            WalkBlock(body, 0, result);
        }
        else if (exprBody is not null)
        {
            ScanExpression(exprBody.Expression, 0, result);
        }

        _results.Add(result);
    }

    private void WalkBlock(BlockSyntax block, int nesting, FunctionComplexity result)
    {
        foreach (var statement in block.Statements)
        {
            ProcessStatement(statement, nesting, result);
        }
    }

    private void WalkStatements(SyntaxList<StatementSyntax> statements, int nesting, FunctionComplexity result)
    {
        foreach (var statement in statements)
        {
            ProcessStatement(statement, nesting, result);
        }
    }

    private void ProcessStatement(StatementSyntax statement, int nesting, FunctionComplexity result)
    {
        switch (statement)
        {
            // ── if / else if / else ─────────────────────────────────
            case IfStatementSyntax ifStmt:
                Add(result, ifStmt.IfKeyword, 1, nesting, "if");
                ScanExpression(ifStmt.Condition, nesting, result);
                ProcessEmbeddedStatement(ifStmt.Statement, nesting + 1, result);
                ProcessElseClause(ifStmt.Else, nesting, result);
                break;

            // ── for ─────────────────────────────────────────────────
            case ForStatementSyntax forStmt:
                Add(result, forStmt.ForKeyword, 1, nesting, "for");
                ProcessEmbeddedStatement(forStmt.Statement, nesting + 1, result);
                break;

            // ── foreach ─────────────────────────────────────────────
            case ForEachStatementSyntax foreachStmt:
                Add(result, foreachStmt.ForEachKeyword, 1, nesting, "foreach");
                ProcessEmbeddedStatement(foreachStmt.Statement, nesting + 1, result);
                break;

            // ── while ───────────────────────────────────────────────
            case WhileStatementSyntax whileStmt:
                Add(result, whileStmt.WhileKeyword, 1, nesting, "while");
                ScanExpression(whileStmt.Condition, nesting, result);
                ProcessEmbeddedStatement(whileStmt.Statement, nesting + 1, result);
                break;

            // ── do-while ────────────────────────────────────────────
            case DoStatementSyntax doStmt:
                Add(result, doStmt.DoKeyword, 1, nesting, "do-while");
                ScanExpression(doStmt.Condition, nesting, result);
                ProcessEmbeddedStatement(doStmt.Statement, nesting + 1, result);
                break;

            // ── switch statement — +1 for the whole structure ───────
            case SwitchStatementSyntax switchStmt:
                Add(result, switchStmt.SwitchKeyword, 1, nesting, "switch");
                foreach (var section in switchStmt.Sections)
                {
                    WalkStatements(section.Statements, nesting + 1, result);
                }
                break;

            // ── try / catch / finally ───────────────────────────────
            case TryStatementSyntax tryStmt:
                // try itself does NOT increment
                if (tryStmt.Block is not null)
                {
                    WalkBlock(tryStmt.Block, nesting, result);
                }
                foreach (var catchClause in tryStmt.Catches)
                {
                    Add(result, catchClause.CatchKeyword, 1, nesting, "catch");
                    WalkBlock(catchClause.Block, nesting + 1, result);
                }
                if (tryStmt.Finally is not null)
                {
                    WalkBlock(tryStmt.Finally.Block, nesting, result);
                }
                break;

            // ── goto — flat +1 ──────────────────────────────────────
            case GotoStatementSyntax gotoStmt:
                Add(result, gotoStmt.GotoKeyword, 1, 0, "goto");
                break;

            // ── return with expression — scan the expression ────────
            case ReturnStatementSyntax returnStmt:
                if (returnStmt.Expression is not null)
                {
                    ScanExpression(returnStmt.Expression, nesting, result);
                }
                break;

            // ── local function declaration ──────────────────────────
            case LocalFunctionStatementSyntax localFunc:
                // Tracked as a separate function result
                var funcResult = new FunctionComplexity(localFunc.Identifier.Text,
                    localFunc.GetLocation().GetLineSpan().StartLinePosition.Line + 1);
                if (localFunc.Body is not null)
                {
                    WalkBlock(localFunc.Body, 0, funcResult);
                }
                else if (localFunc.ExpressionBody is not null)
                {
                    ScanExpression(localFunc.ExpressionBody.Expression, 0, funcResult);
                }
                _results.Add(funcResult);
                break;

            // ── expression statement — scan for ternaries, lambdas, etc.
            case ExpressionStatementSyntax exprStmt:
                ScanExpression(exprStmt.Expression, nesting, result);
                break;

            // ── local declaration — scan initializers ───────────────
            case LocalDeclarationStatementSyntax localDecl:
                foreach (var variable in localDecl.Declaration.Variables)
                {
                    if (variable.Initializer is not null)
                    {
                        ScanExpression(variable.Initializer.Value, nesting, result);
                    }
                }
                break;

            // ── using statement ─────────────────────────────────────
            case UsingStatementSyntax usingStmt:
                // Increases nesting but no increment (like Python's `with`)
                ProcessEmbeddedStatement(usingStmt.Statement, nesting + 1, result);
                break;

            // ── lock statement ──────────────────────────────────────
            case LockStatementSyntax lockStmt:
                ProcessEmbeddedStatement(lockStmt.Statement, nesting + 1, result);
                break;

            // ── block (braces only) ─────────────────────────────────
            case BlockSyntax block:
                WalkBlock(block, nesting, result);
                break;

            // ── everything else — walk children generically ─────────
            default:
                foreach (var child in statement.ChildNodes())
                {
                    if (child is StatementSyntax childStmt)
                    {
                        ProcessStatement(childStmt, nesting, result);
                    }
                    else if (child is ExpressionSyntax childExpr)
                    {
                        ScanExpression(childExpr, nesting, result);
                    }
                }
                break;
        }
    }

    // ── Embedded statement (can be block or single statement) ────────────

    private void ProcessEmbeddedStatement(StatementSyntax statement, int nesting, FunctionComplexity result)
    {
        if (statement is BlockSyntax block)
        {
            WalkBlock(block, nesting, result);
        }
        else
        {
            ProcessStatement(statement, nesting, result);
        }
    }

    // ── else / else-if chain ────────────────────────────────────────────

    private void ProcessElseClause(ElseClauseSyntax? elseClause, int nesting, FunctionComplexity result)
    {
        if (elseClause is null) return;

        if (elseClause.Statement is IfStatementSyntax elseIf)
        {
            // else if — +1 flat, no nesting penalty (like elif)
            Add(result, elseClause.ElseKeyword, 1, 0, "else if");
            ScanExpression(elseIf.Condition, nesting, result);
            ProcessEmbeddedStatement(elseIf.Statement, nesting + 1, result);
            ProcessElseClause(elseIf.Else, nesting, result);
        }
        else
        {
            // plain else — +1 flat
            Add(result, elseClause.ElseKeyword, 1, 0, "else");
            ProcessEmbeddedStatement(elseClause.Statement, nesting + 1, result);
        }
    }

    // ── Expression scanning (ternaries, booleans, lambdas) ──────────────

    private void ScanExpression(ExpressionSyntax expr, int nesting, FunctionComplexity result)
    {
        switch (expr)
        {
            // ── ternary: a ? b : c — +1 with nesting penalty ────────
            case ConditionalExpressionSyntax ternary:
                Add(result, ternary.QuestionToken, 1, nesting, "ternary (?:)");
                ScanExpression(ternary.Condition, nesting + 1, result);
                ScanExpression(ternary.WhenTrue, nesting + 1, result);
                ScanExpression(ternary.WhenFalse, nesting + 1, result);
                break;

            // ── boolean operators: && and || ────────────────────────
            // +1 per sequence of same operator, +1 when operator changes
            case BinaryExpressionSyntax binary when
                binary.IsKind(SyntaxKind.LogicalAndExpression) ||
                binary.IsKind(SyntaxKind.LogicalOrExpression):
                ProcessBooleanExpression(binary, result);
                break;

            // ── null-coalescing ?? — no increment per spec ──────────
            case BinaryExpressionSyntax binary when binary.IsKind(SyntaxKind.CoalesceExpression):
                ScanExpression(binary.Left, nesting, result);
                ScanExpression(binary.Right, nesting, result);
                break;

            // ── lambda / anonymous function — +1 nesting ────────────
            case SimpleLambdaExpressionSyntax lambda:
                Add(result, lambda.ArrowToken, 1, nesting, "lambda");
                ScanLambdaBody(lambda.Body, nesting + 1, result);
                break;

            case ParenthesizedLambdaExpressionSyntax lambda:
                Add(result, lambda.ArrowToken, 1, nesting, "lambda");
                ScanLambdaBody(lambda.Body, nesting + 1, result);
                break;

            case AnonymousMethodExpressionSyntax anonMethod:
                Add(result, anonMethod.DelegateKeyword, 1, nesting, "anonymous method");
                if (anonMethod.Body is BlockSyntax anonBlock)
                {
                    WalkBlock(anonBlock, nesting + 1, result);
                }
                break;

            // ── switch expression (C# 8+) — +1 for the whole thing ──
            case SwitchExpressionSyntax switchExpr:
                Add(result, switchExpr.SwitchKeyword, 1, nesting, "switch expression");
                foreach (var arm in switchExpr.Arms)
                {
                    ScanExpression(arm.Expression, nesting + 1, result);
                    if (arm.WhenClause is not null)
                    {
                        ScanExpression(arm.WhenClause.Condition, nesting + 1, result);
                    }
                }
                break;

            // ── generic recursion into child expressions ────────────
            default:
                foreach (var child in expr.ChildNodes().OfType<ExpressionSyntax>())
                {
                    ScanExpression(child, nesting, result);
                }
                break;
        }
    }

    private void ScanLambdaBody(CSharpSyntaxNode body, int nesting, FunctionComplexity result)
    {
        if (body is BlockSyntax block)
        {
            WalkBlock(block, nesting, result);
        }
        else if (body is ExpressionSyntax expr)
        {
            ScanExpression(expr, nesting, result);
        }
    }

    // ── Boolean operator sequences ──────────────────────────────────────
    // `a && b && c` → +1 (one sequence of &&)
    // `a && b || c` → +2 (switch from && to ||)
    // `a || b || c && d` → +2

    private void ProcessBooleanExpression(BinaryExpressionSyntax node, FunctionComplexity result)
    {
        // Collect the flat sequence of boolean operators
        var operators = new List<(SyntaxKind Kind, SyntaxToken Token)>();
        FlattenBooleanChain(node, operators);

        // +1 for each contiguous group of same operator
        SyntaxKind? currentKind = null;
        foreach (var (kind, token) in operators)
        {
            if (kind != currentKind)
            {
                var opStr = kind == SyntaxKind.LogicalAndExpression ? "&&" : "||";
                AddSimple(result, token, 1, $"boolean sequence ({opStr})");
                currentKind = kind;
            }
        }
    }

    private void FlattenBooleanChain(
        ExpressionSyntax expr,
        List<(SyntaxKind Kind, SyntaxToken Token)> operators)
    {
        if (expr is BinaryExpressionSyntax binary &&
            (binary.IsKind(SyntaxKind.LogicalAndExpression) ||
             binary.IsKind(SyntaxKind.LogicalOrExpression)))
        {
            FlattenBooleanChain(binary.Left, operators);
            operators.Add((binary.Kind(), binary.OperatorToken));
            FlattenBooleanChain(binary.Right, operators);
        }
        // Non-boolean sub-expressions are leaf nodes — nothing to collect
    }

    // ── Helpers ─────────────────────────────────────────────────────────

    private static void Add(FunctionComplexity result, SyntaxToken token, int increment, int nesting, string reason)
    {
        var lineSpan = token.GetLocation().GetLineSpan();
        var line = lineSpan.StartLinePosition.Line + 1;
        var col = lineSpan.StartLinePosition.Character + 1;
        result.Details.Add(new ComplexityDetail(line, col, increment, nesting, reason));
    }

    private static void AddSimple(FunctionComplexity result, SyntaxToken token, int increment, string reason)
    {
        Add(result, token, increment, 0, reason);
    }
}
