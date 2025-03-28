import xml.etree.ElementTree as ET
import sys

def convert_xml_to_sdl(xml_file, target_guid):
    try:
        tree = ET.parse(xml_file)
        root = tree.getroot()
    except Exception as e:
        print(f"Error parsing XML file: {e}")
        sys.exit(1)

    xml_to_sdl_mapping = {
        "a": "a",
        "b": "b",
        "x": "x",
        "y": "y",
        "start": "start",
        "select": "back",
        "hotkeyenable": "guide",
        "leftshoulder": "leftshoulder",
        "rightshoulder": "rightshoulder",
        "lefttrigger": "lefttrigger",
        "righttrigger": "righttrigger",
        "leftstick": "leftstick",
        "rightstick": "rightstick",
        "leftthumb": "leftstick",
        "rightthumb": "rightstick",
        "up": "dpup",
        "down": "dpdown",
        "left": "dpleft",
        "right": "dpright",
        "leftanalogup": None,
        "leftanalogdown": None,
        "leftanalogleft": None,
        "leftanalogright": None,
        "rightanalogup": None,
        "rightanalogdown": None,
        "rightanalogleft": None,
        "rightanalogright": None,
    }

    target_config = None
    for config in root.findall("inputConfig"):
        if config.get("deviceGUID") == target_guid:
            target_config = config
            break

    if not target_config:
        print(f"Error: No configuration found for GUID {target_guid}.")
        sys.exit(1)

    sdl_entries = []
    axis_map = {}
    used_button_ids = set()
    hotkey_buttons = []

    for input_elem in target_config.findall("input"):
        xml_name = input_elem.get("name")
        input_type = input_elem.get("type")
        input_id = input_elem.get("id")
        sdl_name = xml_to_sdl_mapping.get(xml_name)

        if input_type == "axis":
            value = input_elem.get("value")
            invert = False
            if value is not None:
                value = int(value)
                dirs = {
                    "leftanalogup": (value > 0),
                    "leftanalogdown": (value < 0),
                    "leftanalogleft": (value > 0),
                    "leftanalogright": (value < 0),
                    "rightanalogup": (value > 0),
                    "rightanalogdown": (value < 0),
                    "rightanalogleft": (value > 0),
                    "rightanalogright": (value < 0),
                }
                invert = dirs.get(xml_name, False)

            axis_mapping = {
                "leftanalogleft": "leftx",
                "leftanalogright": "leftx",
                "leftanalogup": "lefty",
                "leftanalogdown": "lefty",
                "rightanalogleft": "rightx",
                "rightanalogright": "rightx",
                "rightanalogup": "righty",
                "rightanalogdown": "righty",
            }
            axis_name = axis_mapping.get(xml_name)
            if axis_name and axis_name not in axis_map:
                entry = f"{axis_name}:a{input_id}"
                if invert:
                    entry += "~"
                sdl_entries.append(entry)
                axis_map[axis_name] = True
            continue

        if input_type == "button":
            if xml_name == "hotkeyenable":
                hotkey_buttons.append(input_elem)
                continue

            if sdl_name and input_id not in used_button_ids:
                entry = f"{sdl_name}:b{input_id}"
                sdl_entries.append(entry)
                used_button_ids.add(input_id)
            continue

        if input_type == "hat" and sdl_name:
            hat_value = input_elem.get("value")
            if hat_value:
                entry = f"{sdl_name}:h{input_id}.{hat_value}"
                sdl_entries.append(entry)
            continue

    for input_elem in hotkey_buttons:
        xml_name = input_elem.get("name")
        input_type = input_elem.get("type")
        input_id = input_elem.get("id")
        sdl_name = xml_to_sdl_mapping.get(xml_name)

        if input_type == "button" and sdl_name == "guide" and input_id not in used_button_ids:
            entry = f"{sdl_name}:b{input_id}"
            sdl_entries.append(entry)
            used_button_ids.add(input_id)

    output = f"{target_guid},{target_config.get('deviceName')},platform:Linux,{','.join(sdl_entries)},"
    print(output)

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python script.py <xml_file> <target_guid>")
        sys.exit(1)
    convert_xml_to_sdl(sys.argv[1], sys.argv[2])