/*
	Credits
		Sebastien S. (SystemFailu.re) : Creating main script, reversing engine.
		ellomenop : Doing splits, helping test & misc. bug fixes.

		gwyndol1n : added chamber data extensions
*/

state("Hades")
{
	/*
		There's nothing here because I don't want to use static instance addresses..
		Please refer to `init` to see the signature scanning.
	*/
}

startup
{
	// Credits: Doom asl I found
	vars.ReadOffset = (Func<Process, IntPtr, int, int, IntPtr>)((proc, ptr, offsetSize, remainingBytes) =>
	{
		byte[] offsetBytes;
		if (ptr == IntPtr.Zero || !proc.ReadBytes(ptr, offsetSize, out offsetBytes))
			return IntPtr.Zero;
		return ptr + offsetSize + remainingBytes + BitConverter.ToInt32(offsetBytes, 0);
	});

	// Settings Definition
	settings.Add("extra_info", false, "Extra Chamber Info");
	settings.CurrentDefaultParent = "extra_info";

	settings.Add("chamber_count", true, "Show Chamber Count");
	settings.Add("chaos_gates_count", true, "Show Chaos Gate Count");

	settings.Add("story_chamber_count", true, "Show Story Chamber Count");
	settings.SetToolTip("story_chamber_count", "Sisyphus, Eurydice, and Patroclus");

	settings.Add("fountain_count", true, "Show Fountain Chamber Count");
	settings.SetToolTip("fountain_count", "Excludes Styx fountain");

	settings.Add("map_name", true, "Show Current Map Name");

	settings.Add("boss_count", true, "Show Slow Boss Count");
	settings.SetToolTip("boss_count", "Slow bosses: Tiny Vermin, Barge of Death, Asterius mini-boss");

	settings.Add("logger", true, "Show Logging Information");
	settings.SetToolTip("logger", "Currently set to show `block_name`");

	settings.Add("timer_labels", true, "Create missing text components underneath timer");

	// find where the timer is in livesplit layout; used to place generated labels underneath if wanted
	foreach (dynamic component in timer.Layout.Components) {
		if (component.GetType().Name != "SplitsComponent") continue;
		if (component.GetType().Name == "SplitsComponent") vars.timerIndex = timer.Layout.Components.ToList().IndexOf(component);
	}
}

init
{
	/* Do our signature scanning */

	var engine = modules.Single(x => String.Equals(x.ModuleName, "EngineWin64s.dll", StringComparison.OrdinalIgnoreCase));
	var app_sig_target = new SigScanTarget(3, "48 8B 05 ?? ?? ?? ?? 74 0A"); // rip = 7
	var world_sig_target = new SigScanTarget(3, "48 89 05 ?? ?? ?? ?? 83 78 0C 00 7E 40");
	var playermanager_sig_target = new SigScanTarget(3, "4C 8B 05 ?? ?? ?? ?? 48 8B CB ");
	var signature_scanner = new SignatureScanner(game, engine.BaseAddress, engine.ModuleMemorySize);
	var app_sig_ptr = signature_scanner.Scan(app_sig_target);
	var world_sig_ptr = signature_scanner.Scan(world_sig_target);
	var playermanager_sig_ptr = signature_scanner.Scan(playermanager_sig_target);
	var app_ptr_ref = vars.ReadOffset(game, app_sig_ptr, 4, 0);
	var world_ptr_ref = vars.ReadOffset(game, world_sig_ptr, 4, 0);
	var playermanager_ptr_ref = vars.ReadOffset(game, playermanager_sig_ptr, 4, 0);
	vars.app = ExtensionMethods.ReadPointer(game, app_ptr_ref);
	vars.world = ExtensionMethods.ReadPointer(game, world_ptr_ref); // Just dereference ptr
	vars.playermanager = ExtensionMethods.ReadPointer(game, playermanager_ptr_ref);

	vars.screen_manager = ExtensionMethods.ReadPointer(game, vars.app + 0x3E0); // This might change, but unlikely. We can add signature scanning for this offset if it does. -> F3 44 0F 11 40 ? 49 8B 8F ? ? ? ?
	vars.current_player = ExtensionMethods.ReadPointer(game, ExtensionMethods.ReadPointer(game, vars.playermanager + 0x18));

	vars.current_block_count = ExtensionMethods.ReadValue<int>(game, vars.current_player + 0x50);

	/* Misc. vars */
	vars.split = 0;
	vars.current_run_time = "0:0.0";
	vars.current_map = "";
	vars.current_total_seconds = 0;
	vars.can_move_counter = 0;
	vars.has_beat_hades = false;

	// Additional variables for extensions
	if (settings["extra_info"]) {
		// Barge room: B_Wrapping01
		// Fountain room: Reprieve
		// Shop: Shop/PreBoss
		// Asterius: C_MiniBoss01
		// Tiny Vermin: D_MiniBoss03
		vars.starting_rooms = new string[] {"DeathArea", "DeathAreaBedroom", "RoomPreRun", "RoomOpening"};
		vars.boss_rooms = new string[] {"C_MiniBoss01", "D_MiniBoss03"};
		vars.textSettings = new Dictionary<string, Dictionary<string, dynamic>>
		{
			{
				"chamber_number",
				new Dictionary<string, dynamic>
				{
					{"Id", "chamber_number"},
					{"Name", "Chamber:"},
					{"Settings", null},
					{"Value", 1}
				}
			},
			{
				"chaos_gates", 
				new Dictionary<string, dynamic> 
				{ 
					{"Id", "chaos_gates"}, 
					{"Name", "Chaos Gates:"}, 
					{"Settings", null}, 
					{"Value", 0}
				}
			},
			{
				"story_chambers", 
				new Dictionary<string, dynamic> 
				{ 
					{"Id", "story_chambers"}, 
					{"Name", "Story Chambers:"}, 
					{"Settings", null}, 
					{"Value", 0} 
				}
			},
			{
				"map_name", 
				new Dictionary<string, dynamic>
				{ 
					{"Id", "map_name"}, 
					{"Name", "Map:"}, 
					{"Settings", null}, 
					{"Value", "none"} 
				}
			},
			{
				"fountain_count",
				new Dictionary<string, dynamic>
				{ 
					{"Id", "fountain_count"},
					{"Name", "Fountains:"}, 
					{"Settings", null}, 
					{"Value", 0} 
				}
			},
			{
				"boss_count",
				new Dictionary<string, dynamic>
				{ 
					{"Id", "boss_count"}, 
					{"Name", "Slow Bosses:"}, 
					{"Settings", null}, 
					{"Value", 0} 
				}
			},
			{
				"logger", 
				new Dictionary<string, dynamic>
				{ 
					{"Id", "logger"}, 
					{"Name", "Log:"}, 
					{"Settings", null}, 
					{"Value", ""} 
				}
			}
		};
		
		// wrapper method to update all extra components, calling UpdateComponent foreach TextSetting
		vars.UpdateAllComponents = (Action<Process>)((proc) => {
			foreach (dynamic setting in vars.textSettings)
			{
				vars.UpdateComponent(proc, setting.Value);
			}
		});

		// will create component if none found
		vars.UpdateComponent = (Action<Process, dynamic>)((proc, ts) => {
			// if no component set in TextSetting, find existing component
			if (ts["Settings"] == null) {
				foreach (dynamic component in timer.Layout.Components)
				{
					if (component.GetType().Name != "TextComponent") continue;
					if (component.Settings.Text1 == ts["Name"]) ts["Settings"] = component.Settings;
				}

				// if still not found, create it
				if (ts["Settings"] == null) {
					ts["Settings"] = vars.CreateTextComponent(ts["Name"]);
				}
			}
			// set value of component
			ts["Settings"].Text2 = ts["Value"].ToString();
		});

		// utility function for creating text components in livesplit layout
		// from: https://github.com/Coltaho/Autosplitters/blob/master/MegaMan11/MM11autosplit.asl
		vars.CreateTextComponent = (Func<string, dynamic>)((name) => {
			var textComponentAssembly = Assembly.LoadFrom("Components\\LiveSplit.Text.dll");
			dynamic textComponent = Activator.CreateInstance(textComponentAssembly.GetType("LiveSplit.UI.Components.TextComponent"), timer);
			if (settings["timer_labels"] == false) {
				vars.timerIndex = timer.Layout.Components.ToArray().Length;
			}
			timer.Layout.LayoutComponents.Insert(vars.timerIndex + 1, new LiveSplit.UI.Components.LayoutComponent("LiveSplit.Text.dll", textComponent as LiveSplit.UI.Components.IComponent));
			textComponent.Settings.Text1 = name;
			return textComponent.Settings;
		});
	}
}

update
{
	int last_block_count = vars.current_block_count;
	vars.current_block_count = ExtensionMethods.ReadValue<int>(game, vars.current_player + 0x50);

	/* Check if hash table size has changed */
	if (last_block_count != vars.current_block_count)
	{
		IntPtr hash_table = ExtensionMethods.ReadPointer(game, vars.current_player + 0x40);
		for (int i = 0; i < 2; i++)
		{
			IntPtr block = ExtensionMethods.ReadPointer(game, hash_table + 0x8 * i);
			if (block == IntPtr.Zero)
				continue;
			var block_name = ExtensionMethods.ReadString(game, block, 32); // Guessing on size

			if (settings["extra_info"] && settings["logger"])
			{
				vars.textSettings["logger"]["Value"] = block_name.ToString();
				vars.UpdateComponent(game, vars.textSettings["logger"]);
			}

			if (block_name.ToString() == "HadesKillPresentation")
				vars.has_beat_hades = true; // Run has finished!
		}
	}

	/* Get our vector pointers, used to iterate through current screens */
	if (vars.screen_manager != IntPtr.Zero)
	{
		IntPtr screen_vector_begin = ExtensionMethods.ReadPointer(game, vars.screen_manager + 0x48);
		IntPtr screen_vector_end = ExtensionMethods.ReadPointer(game, vars.screen_manager + 0x50);
		var num_screens = (screen_vector_end.ToInt64() - screen_vector_begin.ToInt64()) >> 3;
		for (int i = 0; i < num_screens; i++)
		{
			IntPtr current_screen = ExtensionMethods.ReadPointer(game, screen_vector_begin + 0x8 * i);
			if (current_screen == IntPtr.Zero)
				continue;
			IntPtr screen_vtable = ExtensionMethods.ReadPointer(game, current_screen); // Deref to get vtable
			IntPtr get_type_method = ExtensionMethods.ReadPointer(game, screen_vtable + 0x68); // Unlikely to change
			int screen_type = ExtensionMethods.ReadValue<int>(game, get_type_method + 0x1);
			if ((screen_type & 0x7) == 7)
			{
				// We have found the InGameUI screen.
				vars.game_ui = current_screen;
				// Possibly stop loop once this has been found? Not sure if this pointer is destructed anytime.
			}
		}
	}


	/* Get our current run time */
	if (vars.game_ui != IntPtr.Zero)
	{
		IntPtr runtime_component = ExtensionMethods.ReadPointer(game, vars.game_ui + 0x510); // Possible to change if they adjust the UI class
		if (runtime_component != IntPtr.Zero)
		{
			/* This might break if the run goes over 99 minutes T_T */
			vars.old_run_time = vars.current_run_time;
			// Can possibly change. -> 48 8D 8E ? ? ? ? 48 8D 05 ? ? ? ? 4C 8B C0 66 0F 1F 44 00
			vars.current_run_time = ExtensionMethods.ReadString(game, ExtensionMethods.ReadPointer(game, runtime_component + 0xAB8), 0x8);
			if (vars.current_run_time == "PauseScr")
			{
				vars.current_run_time = "0:0.0";
			}
			// print("Time: " + vars.current_run_time.ToString() + ", Last: " + vars.old_run_time.ToString());
		}
	}

	/* Get our current map name */
	if (vars.world != IntPtr.Zero)
	{
		vars.is_running = ExtensionMethods.ReadValue<bool>(game, vars.world); // 0x0
		IntPtr map_data = ExtensionMethods.ReadPointer(game, vars.world + 0xA0); // Unlikely to change.
		if (map_data != IntPtr.Zero)
		{
			vars.old_map = vars.current_map;
			vars.current_map = ExtensionMethods.ReadString(game, map_data + 0x8, 0x10);

			// if we're using extra info
			if (settings["extra_info"]) {
				// set our chamber to 1 when entering opening chambers
				if (Array.IndexOf(vars.starting_rooms, vars.current_map) > -1) 
				{
					vars.textSettings["chamber_number"]["Value"] = 1;
				}
				// else, if room is changing:
				// - iterate chamber number
				// - check if chamber is Secret, Story, Boss, or Fountain and iterate accordingly
				// - update all text components
				else if (vars.old_map != vars.current_map && vars.old_map != "") 
				{
					vars.textSettings["chamber_number"]["Value"]++;
					if (settings["map_name"]) vars.textSettings["map_name"]["Value"] = vars.current_map;
					if (settings["chaos_gates"] && vars.current_map.IndexOf("Secret") > -1) vars.textSettings["chaos_gates"]["Value"]++;
					if (settings["story_chambers"] && vars.current_map.IndexOf("Story") > -1) vars.textSettings["story_chambers"]["Value"]++;
					if (settings["fountain_count"] && vars.current_map.IndexOf("Reprieve") > -1 && vars.current_map.IndexOf("D") == -1) vars.textSettings["fountain_count"]["Value"]++;
					if (settings["boss_count"] && Array.IndexOf(vars.boss_rooms, vars.current_map) > -1 || vars.current_map.IndexOf("Wrapping") > -1) vars.textSettings["boss_count"]["Value"]++;
					// print("Map: " + vars.current_map + ", Last:" + vars.old_map);
					vars.UpdateAllComponents(game);
				}
			}
		}
	}

	/* Unused for now */
	IntPtr player_unit = ExtensionMethods.ReadPointer(game, vars.current_player + 0x18);
	if (player_unit != IntPtr.Zero)
	{
		IntPtr unit_input = ExtensionMethods.ReadPointer(game, player_unit + 0x560); // Could change -> 48 8B 91 ? ? ? ? 88 42 08
	}

	vars.old_total_seconds = vars.current_total_seconds;
	vars.time_split = vars.current_run_time.Split(':', '.');
	/* Convert the string time to singles */
	vars.current_total_seconds = Convert.ToSingle(vars.time_split[0]) * 60 + Convert.ToSingle(vars.time_split[1]) + Convert.ToSingle(vars.time_split[2]) / 100;
}

start
{
	// Start the timer if in the first room and the timer either ticked up from 0, or if the old timer is greater than the new (in case of a dangling value from a previous run)
	return (vars.current_map == "RoomOpening" && (vars.old_total_seconds > vars.current_total_seconds || (vars.old_total_seconds == 0 && vars.current_total_seconds != 0)));
}

split
{
	// Credits: ellomenop
	// 1st Split if old map was one of the furies fights and new room is the Tartarus -> Asphodel mid biome room
	if (((vars.old_map == "A_Boss01" || vars.old_map == "A_Boss02" || vars.old_map == "A_Boss03") && vars.current_map == "A_PostBoss01" && vars.split == 0)
	||
	// 2nd Split if old map was lernie (normal or EM2) and new room is the Asphodel -> Elysium mid biome room
	((vars.old_map == "B_Boss01" || vars.old_map == "B_Boss02") && vars.current_map == "B_PostBoss01" && vars.split == 1)
	||
	// 3rd Split if old map was heroes and new room is the Elysium -> Styx mid biome room
	(vars.old_map == "C_Boss01" && vars.current_map == "C_PostBoss01" && vars.split == 2)
	||
	// 4th Split if old map was the styx hub and new room is the dad fight
	(vars.old_map == "D_Hub" && vars.current_map == "D_Boss01" && vars.split == 3)
	||
	// 5th and final split if we have beat dad
	(vars.current_map == "D_Boss01" && vars.has_beat_hades && vars.split == 4))
	{
		vars.split++;
		return true;
	}
}

reset
{
	// Reset and clear state if Zag is currently in the courtyard
	if (vars.current_map == "RoomPreRun")
	{
		/* Reset all of our dynamic variables. */
		vars.split = 0;
		vars.time_split = "0:0.0".Split(':', '.');
		vars.current_total_seconds = 0;
		vars.can_move_counter = 0;
		vars.has_beat_hades = false;
		// Reset extension variables
		foreach (KeyValuePair<string, Dictionary<string, dynamic>> setting in vars.textSettings)
		{
			setting.Value["Value"] = 0;
		}
		return true;
	}
}

gameTime
{
	int h = Convert.ToInt32(vars.time_split[0]) / 60;
	int m = Convert.ToInt32(vars.time_split[0]) % 60;
	int s = Convert.ToInt32(vars.time_split[1]);
	int ms = Convert.ToInt32(vars.time_split[2] + "0");

	return new TimeSpan(0, h, m, s, ms);
}
