#if defined _tf2_hungry_heavy_delivery_included
  #endinput
#endif
#define _tf2_hungry_heavy_delivery_included

//Globals

////////////////////////////
//Natives

/**
 * Returns the top speed of the player.
 * 
 * @param client		Client index.
 * 
 * @return				The top speed of the player.
**/
native float HHD_GetTopSpeed(int client);

/**
 * Returns the total amount of pizzas the player has for the current round.
 * 
 * @param client		Client index.
 * 
 * @return				The total amount of pizzas the player has for the current round.
**/
native int HHD_GetTotalPizzas(int client);

/**
 * Returns the total amount of times a player has climbed a tower during a round.
 * 
 * @param client		Client index.
 * 
 * @return				The total amount of times a player has climbed a tower during a round.
**/
native int HHD_GetTotalClimbs(int client);

/**
 * Returns the current destination of the player.
 * 
 * @param client		Client index.
 * 
 * @return				The current destination of the player.
**/
native int HHD_GetCurrentDestination(int client);

////////////////////////////
//Forwards

/**
* Called as soon as a player lands on the ground while airtime is active.
*
* param client			Client index.
* param time			The time the player was in the air in seconds.
* param record			Whether the time was a new record.
*
* return				N/A
**/
forward void HHD_OnAirtimeLanded(int client, float time, bool record);

#if !defined REQUIRE_PLUGIN
public void __pl_tf2_hungry_heavy_delivery_SetNTVOptional()
{
	MarkNativeAsOptional("HHD_GetTopSpeed");
	MarkNativeAsOptional("HHD_GetTotalPizzas");
	MarkNativeAsOptional("HHD_GetTotalClimbs");
	MarkNativeAsOptional("HHD_GetCurrentDestination");
}
#endif

public SharedPlugin __pl_tf2_hungry_heavy_deliveryr =
{
	name = "tf2-hungry-heavy-delivery",
	file = "tf2-hungry-heavy-delivery.smx",
#if defined REQUIRE_PLUGIN
	required = 1
#else
	required = 0
#endif
};