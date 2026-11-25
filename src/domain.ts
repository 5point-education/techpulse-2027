export type RegistrationType = 'visitor' | 'participant';
export type InstitutionType = 'school' | 'college' | 'other' | 'pass_out';
export type RegistrationStatus = 'draft' | 'pending' | 'approved' | 'rejected' | 'revoked';

export interface EventDefinition {
  code: string;
  name: string;
  subtitle: string;
  description: string;
  image: string;
}

export interface TeamEntry {
  eventCode: string;
  teamName: string;
  members: string[];
}

export interface RegistrationInput {
  type: RegistrationType;
  fullName: string;
  email: string;
  phone: string;
  dob: string;
  gender: string;
  category: string;
  institutionType: InstitutionType;
  institutionName: string;
  classYear: string;
  city: string;
  state: string;
  guardianName: string;
  guardianPhone: string;
  consent: boolean;
  eventCodes: string[];
  teams: TeamEntry[];
}

export interface Registration extends RegistrationInput {
  id: string;
  publicId: string;
  ownerId: string;
  status: RegistrationStatus;
  submittedAt: string;
  reviewedAt?: string;
  reviewNote?: string;
  passToken?: string;
  batchRef?: string;
}

export interface BulkRow {
  row: number;
  studentRef: string;
  type: RegistrationType;
  fullName: string;
  email: string;
  phone: string;
  institutionType: InstitutionType;
  institutionName: string;
  classYear: string;
  city: string;
  eventCodes: string[];
  errors: string[];
}

export const EVENTS: EventDefinition[] = [
  { code: 'ROBO_RACE', name: 'Robo Race', subtitle: 'Nitro Circuit', description: 'Build for speed, control and a demanding obstacle circuit.', image: 'assets/videos/line-follower-action.mp4' },
  { code: 'ROBO_SOCCER', name: 'Robo Soccer', subtitle: 'Goalbyte Arena', description: 'Coordinate, defend and score in a fast robot football clash.', image: 'assets/images/poster-events.jpg' },
  { code: 'ROBO_SUMO', name: 'Robo Sumo', subtitle: 'Mech Mayhem', description: 'Out-think and out-push your opponent inside the combat ring.', image: 'assets/images/cybertron_hero_mech.jpg' },
  { code: 'LINE_FOLLOWER', name: 'Line Follower', subtitle: 'Autonomy Run', description: 'Tune sensors and control logic for precise autonomous navigation.', image: 'assets/videos/line-follower-action.mp4' },
  { code: 'WATER_ROCKET', name: 'Water Rocket', subtitle: 'Altitude Challenge', description: 'Engineer a stable pressurised rocket for height and accuracy.', image: 'assets/images/poster-events.jpg' }
];

export const emptyRegistration = (type: RegistrationType): RegistrationInput => ({
  type, fullName: '', email: '', phone: '', dob: '', gender: '', category: type === 'visitor' ? 'Student' : 'Student participant',
  institutionType: 'school', institutionName: '', classYear: '', city: 'Sonarpur', state: 'West Bengal', guardianName: '', guardianPhone: '',
  consent: false, eventCodes: [], teams: []
});

export function validateRegistration(value: RegistrationInput, step = 4): string[] {
  const errors: string[] = [];
  if (step >= 1) {
    if (value.fullName.trim().length < 2) errors.push('Enter the registrant’s full name.');
    if (!/^\S+@\S+\.\S+$/.test(value.email)) errors.push('Enter a valid email address.');
    if (!/^\+?[0-9 ()-]{10,16}$/.test(value.phone)) errors.push('Enter a valid contact number.');
  }
  if (step >= 2) {
    if (!value.institutionName.trim() && !['other', 'pass_out'].includes(value.institutionType)) errors.push('Enter the institution name.');
    if (!value.classYear.trim()) errors.push('Enter a class, year or designation.');
    if (!value.city.trim()) errors.push('Enter a city or district.');
  }
  if (step >= 3 && value.type === 'participant' && value.eventCodes.length === 0) errors.push('Select at least one competition.');
  if (step >= 4 && !value.consent) errors.push('Accept the declaration before submitting.');
  return errors;
}

export function makePublicId(type: RegistrationType) {
  const chars = crypto.randomUUID().replaceAll('-', '').slice(0, 7).toUpperCase();
  return `TP27-${type === 'visitor' ? 'V' : 'P'}-${chars}`;
}
