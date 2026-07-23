// DOWNGRADE NOTES (Godot 4.2 -> 3.6.2 Mono):
//  - File-scoped 'namespace Destructibles;' + 'using DampMode = RigidBody3D.DampMode;' removed
//    (C# 7.3 / net472 has no file-scoped namespaces; Godot 3 RigidBody has no DampMode enum).
//  - The shared 'global using Godot/System.Threading.Tasks' (from Destructible.cs) -> explicit usings.
//  - Node3D -> Spatial, MeshInstance3D -> MeshInstance, CollisionShape3D -> CollisionShape.
//  - Position -> Translation. Instantiate<T>() -> Instance<T>().
//  - C#9 'is not MeshInstance3D' rewritten for C# 7.3.
//  - Callable.From(() => {...}).CallDeferred() -> named public methods + CallDeferred(nameof(...)). Captured state
//    (settings, shards, saveShardDir) is stored on the instance because CallDeferred marshals args to Godot
//    Variants, which cannot carry the plain-C# ShardSettings object.
//  - DirAccess -> Directory; GD.PrintRich -> GD.Print. Task.Run converted to SYNCHRONOUS main-thread
//    generation for HTML5 (web is single-threaded); CallDeferred marshalling preserved.
using Godot;
using System.Threading.Tasks;

namespace Destructibles
{
	// Used to generate shards both dynamically and statically (for pre-generated use-cases)
	[Tool]
	public partial class DestructibleUtils : Node
	{
		// DOWNGRADE NOTE: instance state used by the deferred SetupShard/FinalizeGeneration callbacks.
		private ShardSettings _settings;
		private Spatial _shards; // DOWNGRADE NOTE: Node3D -> Spatial
		private string _saveShardDir;

		public Task<Spatial> CreateShards(ShardSettings settings) // DOWNGRADE NOTE: Task<Node3D> -> Task<Spatial>; 'async' removed for web.
		{
			_settings = settings;
			// Creates new shards holder and sets the name to be that of the object + Shards
			var saveShardDir = settings.SaveDirectory;
			_shards = new Spatial
			{
				Name = settings.Obj.Name + "Shards"
			};

			// Adds a slash if directory doesn't end with one since the file explorer doesn't give a final slash when using it to set directory.
			if (!saveShardDir.EndsWith("/"))
				saveShardDir += "/";

			// Sets the save directory to be the given directory + Shards.tscn
			saveShardDir += settings.Obj.Name + "Shards.tscn";
			_saveShardDir = saveShardDir;

			// WEB-SAFE: synchronous (was Task.Run). HTML5/web is single-threaded, so the shard-mesh
			// generation that previously ran off-thread now executes inline on the main thread.
			// The CallDeferred() calls below are kept so node mutation (SetupShard/FinalizeGeneration)
			// still happens on the main thread, matching the original deferred marshalling.
			// Runs a loop for all of the children of the scene used to create the shards (should only be MeshInstances)
			foreach (var shardMesh in settings.Obj.GetChildren())
			{
				// Returns if no MeshInstance is found
				// DOWNGRADE NOTE: C#9 'is not MeshInstance3D mesh' -> C# 7.3 negated pattern; MeshInstance3D -> MeshInstance.
				if (!(shardMesh is MeshInstance mesh))
					continue;

				// Instantiates a new shard
				var shardMeshTyped = mesh;
				Shard newShard = settings.ShardScene.Instance<Shard>(); // DOWNGRADE NOTE: Instantiate<Shard>() -> Instance<Shard>()

				// Calls the scene functions deferred for thread safety.
				// DOWNGRADE NOTE: Callable.From(() => {...}).CallDeferred() -> CallDeferred(nameof(SetupShard), ...).
				// Both args are Godot objects (MeshInstance/Shard), so they marshal as Variants.
				CallDeferred(nameof(SetupShard), shardMeshTyped, newShard);
			}

			// DOWNGRADE NOTE: Callable.From(() => {...}).CallDeferred() -> CallDeferred(nameof(FinalizeGeneration)).
			CallDeferred(nameof(FinalizeGeneration));

			// DOWNGRADE NOTE: was 'await Task.Run(...); return _shards;' — now synchronous; return a completed task.
			return Task.FromResult(_shards);
		}

		// DOWNGRADE NOTE: extracted from the first Callable.From(() => {...}).CallDeferred() lambda. Runs on the main thread.
		public void SetupShard(MeshInstance shardMeshTyped, Shard newShard)
		{
			// Sets the shards mesh instance to be that of the objects and adds it as a child of the shard
			var meshInstance = new MeshInstance // DOWNGRADE NOTE: MeshInstance3D -> MeshInstance
			{
				Mesh = shardMeshTyped.Mesh,
				Scale = _settings.Scale,
				Name = "MeshInstance"
			};
			newShard.AddChild(meshInstance);

			// Sets the shards collision shape to be a generation of the mesh instance with the given variables and adds it as a child.
			var collisionShape = new CollisionShape // DOWNGRADE NOTE: CollisionShape3D -> CollisionShape
			{
				Shape = meshInstance.Mesh.CreateConvexShape(
					_settings.CleanCollisionMesh,
					_settings.SimplifyCollisionMesh),
				Scale = _settings.Scale,
				Name = "CollisionShape"
			};
			newShard.AddChild(collisionShape);

			// Sets all of the shard properties
			newShard.Translation = shardMeshTyped.Translation; // DOWNGRADE NOTE: Position -> Translation
			newShard.CollisionLayer = _settings.CollisionLayers;
			newShard.CollisionMask = _settings.CollisionMasks;
			newShard.FadeDelay = _settings.FadeDelay;
			newShard.ExplosionPower = _settings.ExplosionPower;
			newShard.ExplosionDirection = _settings.ExplosionDirection;
			newShard.Mass = _settings.ShardMass;
			newShard.ShrinkDelay = _settings.ShrinkDelay;
			newShard.ParticleFade = _settings.ParticleFade;
			newShard.LinearDamp = _settings.LinearDampening;
			newShard.AngularDamp = _settings.AngularDampening;
			// DOWNGRADE NOTE: newShard.LinearDampMode/AngularDampMode removed (Godot 3 has no RigidBody.DampMode).

			// Adds the shard to the shard list
			_shards.AddChild(newShard);
		}

		// DOWNGRADE NOTE: extracted from the second Callable.From(() => {...}).CallDeferred() lambda. Runs on the main thread.
		public void FinalizeGeneration()
		{
			// Checks if this is to be saved to a scene (for pre-generation use) and if so, saves it to the given path.
			if (_settings.SaveToScene)
			{
				var savedShards = new PackedScene();
				// DOWNGRADE NOTE: Godot 4 DirAccess.Open(path) + DirAccess.GetOpenError() -> Godot 3 Directory class.
				var dir = new Directory();
				string folder = _settings.SaveDirectory;

				foreach (Node shard in _shards.GetChildren())
				{
					shard.Owner = _shards;
					foreach (Node shardChild in shard.GetChildren())
						shardChild.Owner = _shards;
				}

				// DOWNGRADE NOTE: Godot 4 failed if DirAccess.Open returned null; Godot 3 mirrors that by failing
				// when the save directory does not exist.
				if (!dir.DirExists(folder))
				{
					GD.PrintErr("Save directory does not exist: ", folder);
					return;
				}

				savedShards.Pack(_shards);
				// DOWNGRADE NOTE: Godot 3 ResourceSaver.Save(path, resource) — args swapped vs Godot 4 (resource, path); returns Error.
				ResourceSaver.Save(_saveShardDir, savedShards);
				// DOWNGRADE NOTE: GD.PrintRich (BBCode) -> GD.Print.
				GD.Print("Generation completed.");
			}

			// Necessary to avoid orphan nodes
			_settings.Obj.QueueFree();
		}
	}

	public class ShardSettings
	{
		public Spatial      Obj                   { get; set; } // DOWNGRADE NOTE: Node3D -> Spatial
		public PackedScene  ShardScene            { get; set; }
		public uint         CollisionLayers       { get; set; }
		// DOWNGRADE NOTE: removed DampMode LinearDampMode/AngularDampMode (Godot 3 has no RigidBody.DampMode).
		public uint         CollisionMasks        { get; set; }
		public float        ExplosionPower        { get; set; }
		public Vector3      ExplosionDirection    { get; set; }
		public float        ShardMass             { get; set; }
		public float        FadeDelay             { get; set; }
		public float        ShrinkDelay           { get; set; }
		public bool         ParticleFade          { get; set; }
		public bool         SaveToScene           { get; set; }
		public float        LinearDampening       { get; set; }
		public float        AngularDampening      { get; set; }
		public string       SaveDirectory         { get; set; } = "res://";
		public bool         CleanCollisionMesh    { get; set; } = true;
		public bool         SimplifyCollisionMesh { get; set; } = false;
		public Vector3      Scale                 { get; set; } = new Vector3();
	}
}
