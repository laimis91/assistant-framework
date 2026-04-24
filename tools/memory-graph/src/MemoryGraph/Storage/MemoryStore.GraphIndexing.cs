using MemoryGraph.Graph;
using Microsoft.Data.Sqlite;

namespace MemoryGraph.Storage;

public sealed partial class MemoryStore
{
    private void IndexGraphEntity(Entity entity, SqliteTransaction? transaction = null)
    {
        IndexInFtsCore("entity", entity.Name, entity.Name, string.Join(" ", entity.Observations), entity.Type.ToString(), transaction);
    }
}
