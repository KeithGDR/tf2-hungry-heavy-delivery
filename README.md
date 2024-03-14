# TF2-Hungry-Heavy-Delivery

A new mode revolved around delivering pizzas for Team Fortress 2.

In this mode, players play as delivery boys who are tasked with delivering pizzas to the locals. The primary objectives are to deliver as many pizzas as possible and to achieve maximum airtime by navigating through the map's intricate layout. Success in this mode depends on agility, strategic movement, and sometimes team coordination depending on the gametype.

## Requirements

To run this custom mode, your server must meet the following requirements:

    * SourceMod 1.12 or higher.
    * TF2Items (by Asherkin)
    * TF2Attributes (by FlaminSarge/Nosoop)
    * Downloads Enabled (sv_downloadurl)

## Installation

    SourceMod and Plugins: First, ensure that your server is running SourceMod 1.12 or above. Then, install the TF2Items Extension and the TF2Attributes plugin if you haven't already.

    Custom Content: Download and install the custom content required for the mode. This content must be placed in the custom directory, here's an example path: tf/custom/hhd/
    mode Files: Download the modes files from this repository. Extract and place them in the tf/addons/sourcemod directory on your server.

## Configuration

### Database Configuration

To track player statistics, including pizza deliveries and airtime, the mode utilizes a database. You must configure the database.cfg file accordingly:

    Navigate to addons/sourcemod/configs/databases.cfg.

    Add a new entry for database with the following format:

    "HHD"
    {
        "driver"    "mysql"
        "host"      "YOUR_DATABASE_HOST"
        "database"  "YOUR_DATABASE_NAME"
        "user"      "YOUR_DATABASE_USER"
        "password"  "YOUR_DATABASE_PASSWORD"
        "port"      "3306"
    }

    Replace the placeholders (YOUR_DATABASE_HOST, etc.) with your actual database information.

## Workshop Map

For the optimal experience, it is recommended to use the custom map designed specifically for the mode. This map can be found on the Steam Workshop:

    https://steamcommunity.com/sharedfiles/filedetails/?id=1299919295

Replace XXXXX with the actual item ID of the workshop map. Subscribe to the map and add it to your server's map rotation to make it available for play.

## Support

Once installation and configuration are complete, restart your server. The mode should now be active and playable.
For questions, issues, or contributions, please use the Issues and Pull Requests sections of this GitHub repository.
