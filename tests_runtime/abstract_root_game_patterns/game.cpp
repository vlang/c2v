#include <stdio.h>

class Entity;

class Class {
public:
	virtual ~Class() {}
	virtual const char *KindName() const = 0;
	bool IsEntity() const;
	void Describe() const;
};

enum CommandType { CMD_SOUND, CMD_INDEX };

struct Command {
	CommandType type;
	union {
		const char *soundName;
		int index;
	};
};

class Entity : public Class {
public:
	const char *name;
	int AI_PAIN;
	int AI_DEST_UNREACHABLE;
	Command command;
	Entity() : AI_PAIN(3) { name = "entity"; AI_DEST_UNREACHABLE = 1; command.type = CMD_INDEX; command.index = 5; }
	const char *KindName() const { return "Entity"; }
	const char *GetName() const { return name; }
};

class Monster : public Entity {
public:
	Monster() { name = "monster"; command.type = CMD_SOUND; command.soundName = "growl"; AI_PAIN = 7; }
	const char *KindName() const { return "Monster"; }
};

class Thread : public Class {
public:
	int id;
	Thread() { id = 9; }
	const char *KindName() const { return "Thread"; }
};

bool Class::IsEntity() const {
	const char *type = KindName();
	return type[0] == 'E' || type[0] == 'M';
}

void Class::Describe() const {
	if (IsEntity()) {
		const Entity *entity = static_cast<const Entity *>(this);
		const Command &command = entity->command;
		if (command.type == CMD_SOUND) {
			printf("%s %s sound %s %d %d\n", KindName(), entity->GetName(), command.soundName, entity->AI_PAIN, entity->AI_DEST_UNREACHABLE);
		} else {
			printf("%s %s index %d %d %d\n", KindName(), entity->GetName(), command.index, entity->AI_PAIN, entity->AI_DEST_UNREACHABLE);
		}
	} else {
		printf("%s\n", KindName());
	}
}

int main() {
	Class *objects[3];
	objects[0] = new Entity();
	objects[1] = new Monster();
	objects[2] = new Thread();
	for (int i = 0; i < 3; i++) {
		objects[i]->Describe();
	}
	return 0;
}
