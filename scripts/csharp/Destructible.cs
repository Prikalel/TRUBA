// DOWNGRADE NOTES (Godot 4.2 -> 3.6.2 Mono):
//  - C#10 'global using' directives + file-scoped 'namespace Destructibles;' converted to regular
//    'using' statements + a block namespace (net472 defaults to C# 7.3, which has neither feature).
//  - [GlobalClass] removed (Godot-4-only; the type is now compiled straight into the main assembly).
//  - Node3D -> Spatial, RigidBody3D -> RigidBody, MeshInstance3D -> MeshInstance, CollisionShape3D -> CollisionShape,
//    PhysicsBody3D -> PhysicsBody, Position/GlobalPosition -> Translation / GlobalTransform.origin.
//  - [ExportGroup] removed (absent in Godot 3; kept as comments). PropertyHint.Layers3DPhysics -> Layers3dPhysics.
//  - RigidBody3D.DampMode exports/logic removed (no Godot 3 equivalent; LinearDamp/AngularDamp kept).
//  - Instantiate() -> Instance(); GD.PrintRich -> GD.Print; Callable.From(...).CallDeferred() -> named method + CallDeferred.
//  - Node.TopLevel has no Godot 3 equivalent (approximated via GlobalTransform assignment, see FinalizeDestroy).
using Godot;
using System.Linq;

namespace Destructibles
{
	[Tool]
	public partial class Destructible : Node
	{
		[Export] private PackedScene _fragmented;

		private PackedScene Fragmented
		{
			get => _fragmented;
			set => SetFragmented(value);
		}

		private PackedScene _shard;

		private PackedScene Shard
		{
			get => _shard;
			set => SetShard(value);
		}

		[Export]
		private Node _shardContainer;

		private Node ShardContainer
		{
			get => _shardContainer;
			set => SetShardContainer(value);
		}

		// [ExportGroup("Animation")] (Godot 4 only; removed for Godot 3)
		[Export] private float _fadeDelay = 2f;
		[Export] private float _shrinkDelay = 2f;
		[Export] private bool _particleFade = true;

		// [ExportGroup("Collision")] (Godot 4 only; removed for Godot 3)
		// DOWNGRADE NOTE: PropertyHint.Layers3DPhysics (Godot 4) -> PropertyHint.Layers3dPhysics (Godot 3).
		[Export(PropertyHint.Layers3dPhysics)] private uint _collisionLayers = 1;
		[Export(PropertyHint.Layers3dPhysics)] private uint _layerMasks = 1;


		// [ExportGroup("Generation")] (Godot 4 only; removed for Godot 3)
		[Export] public bool GenerateShards
		{
			get => false;
			set
			{
				if (value)
				{
					_saveToScene = true;
					// DOWNGRADE NOTE: GD.PrintRich (BBCode) -> GD.Print (no rich text in Godot 3).
					GD.Print("Generation started.");
					Destroy();
				}
			}
		}

		[Export] private bool _preloadShards = true;

		[Export(PropertyHint.Dir)] private string _savePath = "res://shard";

		[Export] private bool _cleanCollisionMesh = true;

		[Export] private bool _simplifyCollisionMesh = false;

		[Export] private PackedScene _preGeneratedShards;

		[Export] private float _shardMass = 1f;

		[Export] private float _linearDampening = 0f;
		// DOWNGRADE NOTE: removed [Export] RigidBody3D.DampMode _linearDampMode (no Godot 3 DampMode enum).

		[Export] private float _angularDampening = 0f;
		// DOWNGRADE NOTE: removed [Export] RigidBody3D.DampMode _angularDampMode (no Godot 3 DampMode enum).

		private bool _saveToScene;
		private Vector3 _scale = Vector3.One;
		private Spatial _shards; // DOWNGRADE NOTE: Node3D -> Spatial
		private Spatial _fragmentedInstance; // DOWNGRADE NOTE: Node3D -> Spatial

		public override void _Ready()
		{
			_shardContainer = GetNodeOrNull("../../");
			_scale = GetParent<Spatial>().Scale; // DOWNGRADE NOTE: GetParent<Node3D>() -> GetParent<Spatial>()

			// DOWNGRADE NOTE: shard scene moved out of the (deleted) addons folder into the main project.
			_shard = (PackedScene)GD.Load("res://scripts/csharp/shard.tscn");
			// If preloading shards is enabled instances the correct shards for either dynamic generated or pre-generated shards.
			if (_preGeneratedShards == null && _preloadShards)
			{
				if (_fragmented == null)
				{
					GD.PrintErr("No fragment scene found");
					return;
				}
				_fragmentedInstance = _fragmented.Instance() as Spatial; // DOWNGRADE NOTE: Instantiate() -> Instance(), Node3D -> Spatial
			}
			else if (_preloadShards)
			{
				_shards = _preGeneratedShards.Instance<Spatial>(); // DOWNGRADE NOTE: Instantiate<Node3D>() -> Instance<Spatial>()
			}
		}


		// Destroy function to be called when destroying an object (Also used to handle pre-generation of shards)
		private async void Destroy(float explosionPower = 4f, Vector3 explosionDirection = default(Vector3))
		{
			_shard = (PackedScene)GD.Load("res://scripts/csharp/shard.tscn");
			// Checks if a pre-generated shard scene is given, if not generates the shards with the given options.
			if (_preGeneratedShards == null)
			{
				// Checks if shards are preloaded, if not loads them
				if (!IsInstanceValid(_fragmentedInstance) || _fragmentedInstance == null)
				{
					if (_fragmented != null)
					{
						_fragmentedInstance = _fragmented.Instance() as Spatial;
					}
					else
					{
						GD.PrintErr("No fragmented scene given, aborting!");
						return;
					}
				}

				var destructionUtils = new DestructibleUtils();

				_shards = await destructionUtils.CreateShards(new ShardSettings
				{
					Obj = _fragmentedInstance,
					ShardScene = _shard,
					CollisionLayers = _collisionLayers,
					CollisionMasks = _layerMasks,
					ExplosionPower = explosionPower,
					ExplosionDirection = explosionDirection,
					ShardMass = _shardMass,
					FadeDelay = _fadeDelay,
					ShrinkDelay = _shrinkDelay,
					ParticleFade = _particleFade,
					SaveToScene = _saveToScene,
					LinearDampening = _linearDampening,
					AngularDampening = _angularDampening,
					SaveDirectory = _savePath,
					CleanCollisionMesh = _cleanCollisionMesh,
					SimplifyCollisionMesh = _simplifyCollisionMesh,
					Scale = _scale
					// DOWNGRADE NOTE: LinearDampMode/AngularDampMode removed (Godot 3 has no RigidBody.DampMode).
				});

				destructionUtils.QueueFree(); // Necessary to avoid orphan nodes
				if (_saveToScene)
				{
					return;
				}
			}
			else
			{
				// Checks if shards are preloaded, if not loads them
				if (!_preloadShards)
				{
					_shards = _preGeneratedShards.Instance<Spatial>();
				}

				// Sets the variables on each shard that would otherwise be set when generating the shards dynamically.
				foreach (Node shardNode in _shards.GetChildren())
				{
					var shard = shardNode as Shard;

					shard.CollisionLayer = _collisionLayers;
					shard.CollisionMask = _layerMasks;
					shard.FadeDelay = _fadeDelay;
					shard.ExplosionPower = explosionPower;
					shard.ExplosionDirection = explosionDirection;
					shard.Mass = _shardMass;
					shard.ShrinkDelay = _shrinkDelay;
					shard.ParticleFade = _particleFade;
					shard.LinearDamp = _linearDampening;
					shard.AngularDamp = _angularDampening;
					// DOWNGRADE NOTE: shard.LinearDampMode/AngularDampMode assignments removed (Godot 3 has no DampMode).
				}
			}

			// DOWNGRADE NOTE: Godot 4 Callable.From(() => {...}).CallDeferred() -> Godot 3 named method + CallDeferred.
			CallDeferred(nameof(FinalizeDestroy));
		}


		// DOWNGRADE NOTE: extracted from the Godot 4 Callable.From(() => {...}).CallDeferred() lambda in Destroy().
		public void FinalizeDestroy()
		{
			var parent = GetParent<Spatial>();
			// DOWNGRADE NOTE: Godot 3 has no Node.TopLevel. Equivalent: add the shards holder to the container,
			// then set its GLOBAL transform directly (a GlobalTransform assignment compensates for the parent's
			// transform), matching the Godot 4 intent of placing shards at the original object's world transform.
			// GlobalRotation/GlobalPosition (Godot 4) are reconstructed from GlobalTransform (Godot 3 Spatial has
			// neither). Orthonormalized() yields the parent's rotation without scale, matching GlobalRotation.
			_shardContainer.AddChild(_shards);
			_shards.GlobalTransform = new Transform(
				parent.GlobalTransform.basis.Orthonormalized(),
				parent.GlobalTransform.origin);

			// Necessary to avoid orphan nodes
			GetParent().QueueFree();
		}


		// Sets the fragmented value to the one set in the editor, and checks for errors, if so issuing a warning
		private void SetFragmented(PackedScene to)
		{
			_fragmented = to;

			if (IsInsideTree())
				UpdateConfigurationWarning(); // DOWNGRADE NOTE: singular in Godot 3.

			_Ready();
		}


		// Sets the Shard value to the one set in the editor, and checks for errors, if so issuing a warning
		private void SetShard(PackedScene to)
		{
			_shard = to;

			if (IsInsideTree())
				UpdateConfigurationWarning(); // DOWNGRADE NOTE: singular in Godot 3.

			_Ready();
		}


		// Sets the Shard Container value to the one set in the editor, and checks for errors, if so issuing a warning
		private void SetShardContainer(Node to)
		{
			_shardContainer = to;

			if (IsInsideTree())
				UpdateConfigurationWarning(); // DOWNGRADE NOTE: singular in Godot 3.

			_Ready();
		}


		// Run when an above function issues a warning, passes this warning on to the user.
		// DOWNGRADE NOTE: Godot 3 C# uses _GetConfigurationWarning() returning a SINGLE string (singular),
		// unlike Godot 4's _GetConfigurationWarnings() returning string[]. The original Godot 4 code built a
		// warnings array but discarded it and returned base (so no warnings were ever shown); that behavior
		// is preserved here.
		public override string _GetConfigurationWarning()
		{
			var warnings = new string[] { };

			if (_fragmented == null)
				warnings.Append("No fragmented version set");

			if (_shard == null)
				warnings.Append("No shard template set");

			if (_shardContainer is PhysicsBody || _hasParentOfType(_shardContainer)) // DOWNGRADE NOTE: PhysicsBody3D -> PhysicsBody
				warnings.Append
					("The shard container is a PhysicsBody or has a PhysicsBody " +
					"as a parent. This will make the shards added to it behave " +
					"in unexpected ways.");

			return base._GetConfigurationWarning();
		}

		// Simple function to see if a parent of a given node is a certain type.
		static bool _hasParentOfType(Node node)
		{
			if (node.GetParent() == null)
				return false;

			if (node.GetParent() is PhysicsBody) // DOWNGRADE NOTE: PhysicsBody3D -> PhysicsBody
				return true;

			return _hasParentOfType(node.GetParent());
		}
	}
}
