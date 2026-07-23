// DOWNGRADE NOTES (Godot 4.2 -> 3.6.2 Mono):
//  - File-scoped 'namespace Destructibles;' (C#10) -> block namespace (C# 7.3 / net472).
//  - The shared 'global using Godot;' (from Destructible.cs) is replaced with an explicit 'using Godot;'.
//  - RigidBody3D -> RigidBody, MeshInstance3D -> MeshInstance, StandardMaterial3D -> SpatialMaterial.
//  - Position -> Translation.
//  - C#9 'is not StandardMaterial3D material' rewritten for C# 7.3.
//  - BaseMaterial3D.TransparencyEnum (AlphaHash/AlphaDepthPrePass) has no Godot 3 equivalent; approximated with
//    SpatialMaterial.FlagsTransparent so the albedo alpha fade tween still works.
//  - SceneTree.CreateTween() -> Godot 3 Tween Node. TweenProperty(...).SetDelay/Trans/Ease/.Parallel() ->
//    InterpolateProperty(obj, prop, initial, final, dur, trans, ease, delay) (Godot 3 runs all in parallel by default).
//  - Godot 4 Tween "finished" signal -> Godot 3 Tween "tween_all_completed".
//  - RigidBody.ApplyImpulse arg order swapped: Godot 4 (impulse, position) -> Godot 3 (position, impulse).
using Godot;

namespace Destructibles
{
	[Tool]
	public partial class Shard : RigidBody // DOWNGRADE NOTE: RigidBody3D -> RigidBody
	{
		// Instance variables to be set by the other destruction scripts
		public float ShrinkDelay = -1;
		public float FadeDelay = -1;
		public float ExplosionPower;
		public bool ParticleFade = true;
		public Vector3 ExplosionDirection = Vector3.Zero;

		public override void _Ready()
		{
			// Checks if inside a game or the editor, if in a game runs initialize.
			if (!Engine.EditorHint) // DOWNGRADE NOTE: Godot 3 Engine.IsEditorHint() is deprecated -> Engine.EditorHint property.
				Initialize();
		}


		public async void Initialize()
		{
			// Awaits two physics frames due to this bug https://github.com/godotengine/godot/issues/75934
			// (DOWNGRADE NOTE: the "physics_frame" signal name is identical in Godot 3.)
			await ToSignal(GetTree(), "physics_frame");
			await ToSignal(GetTree(), "physics_frame");

			// If no direction for explosion is given set a random one.
			if (ExplosionDirection == Vector3.Zero)
				ExplosionDirection = RandomDirection();

			// Gets the mesh instance and material for later use
			var meshInstance = GetNode<MeshInstance>("MeshInstance"); // DOWNGRADE NOTE: MeshInstance3D -> MeshInstance
			var materialSurface = meshInstance.Mesh.SurfaceGetMaterial(0);
			// Duplicates material, so tweens don't affect original object / other instances of it.

			// DOWNGRADE NOTE: C#9 'is not StandardMaterial3D material' rewritten for C# 7.3.
			// DOWNGRADE NOTE: StandardMaterial3D -> SpatialMaterial.
			var duplicated = materialSurface.Duplicate(true);
			SpatialMaterial material = duplicated as SpatialMaterial;
			// Returns if no material is found
			if (material == null)
			{
				GD.PrintErr("No material found, returning...");
				return;
			}

			// Sets mesh material to be the new material
			meshInstance.MaterialOverride = material;

			// DOWNGRADE NOTE: Godot 3 SpatialMaterial has no BaseMaterial3D.TransparencyEnum (AlphaHash /
			// AlphaDepthPrePass). We approximate both paths with the transparent flag so the albedo alpha fade
			// tween still works. (The AlphaHash vs AlphaDepthPrePass visual distinction is not preserved; both
			// fade via standard alpha blending.)
			material.FlagsTransparent = true;


			// DOWNGRADE NOTE: Godot 4 SceneTree.CreateTween() -> Godot 3 Tween Node (added as a child).
			var tween = new Tween();
			AddChild(tween);
			// Applies explosion force (if it has any) to the shard.
			// DOWNGRADE NOTE: Godot 3 RigidBody.ApplyImpulse takes (position, impulse) — args swapped vs
			// Godot 4 (impulse, position). Position -> Translation.
			ApplyImpulse(-Translation.Normalized(), ExplosionDirection * ExplosionPower);

			// Run fade tween if fade is enabled (checked through fade delay being greater than 0)
			if (FadeDelay > 0)
			{
				// DOWNGRADE NOTE: Godot 4 tween.TweenProperty(obj, prop, target, dur).SetDelay().SetTrans().SetEase()
				// -> Godot 3 tween.InterpolateProperty(obj, prop, initial, final, dur, trans, ease, delay).
				// Godot 4 animates from the current value automatically, so the initial value is read here.
				tween.InterpolateProperty(material, "albedo_color", material.AlbedoColor, new Color(1, 1, 1, 0), 2f,
					Tween.TransitionType.Expo, Tween.EaseType.Out, FadeDelay);
			}


			// Run shrink tween if shrink is enabled (checked through shrink delay being greater than 0)
			if (ShrinkDelay > 0)
			{
				// DOWNGRADE NOTE: Godot 4 tween.Parallel().TweenProperty(...) -> Godot 3 InterpolateProperty runs
				// in parallel with the fade tween by default.
				tween.InterpolateProperty(meshInstance, "scale", meshInstance.Scale, Vector3.Zero, 2f,
					Tween.TransitionType.Linear, Tween.EaseType.In, ShrinkDelay);
			}

			// DOWNGRADE NOTE: Godot 3 Tween node is started explicitly after registering interpolations.
			tween.Start();

			// Wait for the shard to finish its tween (disappear).
			// DOWNGRADE NOTE: Godot 4 Tween "finished" signal -> Godot 3 Tween "tween_all_completed".
			await ToSignal(tween, "tween_all_completed");

			// Removes shard parent along with all other shards
			GetParent().QueueFree();
		}


		// Simple function to return a random direction
		static Vector3 RandomDirection() =>
			(new Vector3(GD.Randf(), GD.Randf(), GD.Randf()) - Vector3.One / 2.0f)
				.Normalized() * 2.0f;
	}
}
